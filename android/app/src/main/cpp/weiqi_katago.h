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

// Points are row-major, top left first. -1 is a pass. Black is 1, white is 2.
// Ordinary operations are serialized on one worker. Only cancel may run concurrently.
WEIQI_API WeiqiEngine* weiqi_create(const char* model_path, const char* config_path,
                                   int32_t size, char* error, int32_t error_capacity);
WEIQI_API void weiqi_destroy(WeiqiEngine* engine);
WEIQI_API const char* weiqi_error(const WeiqiEngine* engine);
WEIQI_API int32_t weiqi_reset(WeiqiEngine* engine, int32_t size, const int32_t* points,
                              int32_t count, WeiqiPosition* position);
// Returns 1 for an illegal move, 0 for success, and -1 for an engine failure.
WEIQI_API int32_t weiqi_play(WeiqiEngine* engine, int32_t point, WeiqiPosition* position);
// Returns the number of candidates, 0 for cancellation, or -1 for an engine failure.
// The engine's recommendation is first. A search leaves the game history intact.
WEIQI_API int32_t weiqi_search(WeiqiEngine* engine, uint64_t token, int32_t max_visits,
                               double max_seconds, WeiqiCandidate* results, int32_t capacity);
WEIQI_API void weiqi_cancel(WeiqiEngine* engine, uint64_t token);

#ifdef __cplusplus
}
#endif
