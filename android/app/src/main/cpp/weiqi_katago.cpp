#include "weiqi_katago.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <functional>
#include <memory>
#include <mutex>
#include <stdexcept>

#include "neuralnet/nninterface.h"
#include "program/setup.h"

namespace {

bool supportedSize(int size) {
  return size == 9 || size == 13 || size == 19;
}

Loc toLoc(int point, int size) {
  if (point == -1) return Board::PASS_LOC;
  if (point < 0 || point >= size * size) return Board::NULL_LOC;
  return Location::getLoc(point % size, point / size, size);
}

int toPoint(Loc loc, int size) {
  if (loc == Board::PASS_LOC) return -1;
  return Location::getY(loc, size) * size + Location::getX(loc, size);
}

bool play(Board& board, BoardHistory& history, int point) {
  const Loc loc = toLoc(point, board.x_size);
  const Player player = history.presumedNextMovePla;
  if (history.isGameFinished || loc == Board::NULL_LOC ||
      !history.isLegal(board, loc, player)) {
    return false;
  }
  history.makeBoardMoveAssumeLegal(board, loc, player, nullptr);
  return true;
}

void writePosition(const Board& board, const BoardHistory& history, WeiqiPosition& position) {
  const int size = board.x_size;
  position = {};
  position.size = size;
  position.next_player = history.presumedNextMovePla;
  position.finished = history.isGameFinished;
  position.winner = history.winner;
  position.white_minus_black = history.finalWhiteMinusBlackScore;
  for (int point = 0; point < size * size; point++) {
    position.stones[point] = board.colors[toLoc(point, size)];
  }
}

}  // namespace

struct WeiqiEngine {
  ConfigParser config;
  Logger logger;
  Rand random;
  std::string model_path;
  Rules rules;
  SearchParams params;
  Board board;
  BoardHistory history;
  std::unique_ptr<NNEvaluator> evaluator;
  std::atomic<uint64_t> cancelled_through{0};
  std::string error;

  WeiqiEngine(const char* model, const char* cfg, int size)
      : config(cfg), logger(&config), model_path(model),
        rules(Setup::loadSingleRules(config, true)),
        params(Setup::loadSingleParams(config, Setup::SETUP_FOR_GTP)),
        board(size, size), history(board, P_BLACK, rules, 0) {
    loadEvaluator(size);
  }

  void loadEvaluator(int size) {
    if (evaluator && evaluator->getNNXLen() == size) return;

    evaluator.reset();
    evaluator.reset(Setup::initializeNNEvaluator(
        model_path, model_path, "", config, logger, random, params.numThreads,
        size, size, 2, true, true, Setup::SETUP_FOR_GTP));
  }
};

WeiqiEngine* weiqi_create(const char* model_path, const char* config_path,
                          int32_t size, char* error, int32_t error_capacity) {
  try {
    if (!supportedSize(size)) throw std::invalid_argument("Unsupported board size");
    static std::once_flag init;
    std::call_once(init, [] {
      Board::initHash();
      ScoreValue::initTables();
      NeuralNet::globalInitialize();
    });
    return new WeiqiEngine(model_path, config_path, size);
  } catch (const std::exception& e) {
    if (error_capacity > 0) std::snprintf(error, error_capacity, "%s", e.what());
    return nullptr;
  }
}

void weiqi_destroy(WeiqiEngine* engine) {
  delete engine;
}

const char* weiqi_error(const WeiqiEngine* engine) {
  return engine->error.c_str();
}

int32_t weiqi_reset(WeiqiEngine* engine, int32_t size, const int32_t* points,
                     int32_t count, WeiqiPosition* position) {
  try {
    if (!supportedSize(size) || count < 0) throw std::invalid_argument("Invalid saved game");
    Board board(size, size);
    BoardHistory history(board, P_BLACK, engine->rules, 0);
    for (int i = 0; i < count; i++) {
      if (!play(board, history, points[i])) {
        throw std::invalid_argument("Illegal saved move " + std::to_string(i + 1));
      }
    }
    engine->board = board;
    engine->history = std::move(history);
    writePosition(engine->board, engine->history, *position);
    return 0;
  } catch (const std::exception& e) {
    engine->error = e.what();
    return -1;
  }
}

int32_t weiqi_play(WeiqiEngine* engine, int32_t point, WeiqiPosition* position) {
  try {
    if (!play(engine->board, engine->history, point)) return 1;
    writePosition(engine->board, engine->history, *position);
    return 0;
  } catch (const std::exception& e) {
    engine->error = e.what();
    return -1;
  }
}

int32_t weiqi_search(WeiqiEngine* engine, uint64_t token, int32_t max_visits,
                      double max_seconds, WeiqiCandidate* results, int32_t capacity) {
  try {
    if (engine->history.isGameFinished || capacity < 1 ||
        max_visits < 2 || !std::isfinite(max_seconds) || max_seconds <= 0) {
      throw std::invalid_argument("Invalid search");
    }
    std::function<bool()> cancelled = [engine, token] {
      return engine->cancelled_through.load(std::memory_order_relaxed) >= token;
    };
    if (cancelled()) return 0;

    const int size = engine->board.x_size;
    engine->loadEvaluator(size);
    if (cancelled()) return 0;

    SearchParams params = engine->params;
    params.maxVisits = max_visits;
    params.maxTime = max_seconds;
    const Player player = engine->history.presumedNextMovePla;
    Search search(params, engine->evaluator.get(), &engine->logger,
                  std::to_string(engine->random.nextUInt64()));
    search.setPosition(player, engine->board, engine->history);
    search.runWholeSearch(player, &cancelled);
    if (cancelled()) return 0;

    const Loc chosen = search.getChosenMoveLoc();
    if (chosen == Board::NULL_LOC || !engine->history.isLegal(engine->board, chosen, player)) {
      throw std::runtime_error("KataGo did not return a legal move");
    }

    std::vector<AnalysisData> analysis;
    search.getAnalysisData(analysis, 0, false, 1, false);
    results[0] = {toPoint(chosen, size), 0, 0.0};
    int count = 1;
    for (const AnalysisData& move : analysis) {
      if (move.numVisits <= 0 || !std::isfinite(move.utility)) continue;
      const WeiqiCandidate candidate{
          toPoint(move.move, size), static_cast<int32_t>(move.numVisits),
          player == P_WHITE ? move.utility : -move.utility,
      };
      if (move.move == chosen) {
        results[0] = candidate;
      } else if (count < capacity && move.move != Board::PASS_LOC &&
                 engine->history.isLegal(engine->board, move.move, player)) {
        results[count++] = candidate;
      }
    }
    return count;
  } catch (const std::exception& e) {
    engine->error = e.what();
    return -1;
  }
}

void weiqi_cancel(WeiqiEngine* engine, uint64_t token) {
  auto previous = engine->cancelled_through.load(std::memory_order_relaxed);
  while (previous < token &&
         !engine->cancelled_through.compare_exchange_weak(
             previous, token, std::memory_order_relaxed)) {}
}
