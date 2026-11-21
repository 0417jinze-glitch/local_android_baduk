#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WEIQI_API __attribute__((visibility("default")))

typedef struct WeiqiEngine WeiqiEngine;

typedef struct {
  int32_t size;
  int32_t next_player;
  int32_t finished;
  int32_t winner;
  double white_minus_black;
  uint8_t stones[19 * 19];
} WeiqiPosition;

typedef struct {
  int32_t point;
  int32_t visits;
  double utility;
} WeiqiCandidate;

enum { WEIQI_MAX_CANDIDATES = 16 };

typedef struct {
  double white_lead;
  int32_t count;
  WeiqiCandidate candidates[WEIQI_MAX_CANDIDATES];
  int32_t ownership_count;
  float white_ownership[19 * 19];
} WeiqiSearchResult;

// Points are row-major, top left first. -1 is a pass. Black is 1, white is 2.
// Ordinary operations are serialized on one worker. Only cancel may run concurrently.
WEIQI_API WeiqiEngine* weiqi_create(const char* model_path, const char* config_path,
                                   int32_t size, char* error, int32_t error_capacity);
WEIQI_API void weiqi_destroy(WeiqiEngine* engine);
WEIQI_API const char* weiqi_error(const WeiqiEngine* engine);
WEIQI_API int32_t weiqi_set_model(WeiqiEngine* engine, const char* model_path, int32_t size);
WEIQI_API int32_t weiqi_reset(WeiqiEngine* engine, int32_t size, const int32_t* points,
                              int32_t count, WeiqiPosition* position);
// Returns 1 for an illegal move, 0 for success, and -1 for an engine failure.
WEIQI_API int32_t weiqi_play(WeiqiEngine* engine, int32_t point, WeiqiPosition* position);
// Returns 1 for success, 0 for cancellation, or -1 for an engine failure.
// White lead is in points, with NaN meaning unavailable. A search leaves history intact.
// Ownership is row-major, with negative values favoring black and positive values favoring white.
// When candidates are requested, the engine's recommendation is first.
WEIQI_API int32_t weiqi_search(WeiqiEngine* engine, uint64_t token, int32_t max_visits,
                               double max_seconds, int32_t include_candidates,
                               WeiqiSearchResult* result);
WEIQI_API void weiqi_cancel(WeiqiEngine* engine, uint64_t token);

#ifdef __cplusplus
}
#endif
