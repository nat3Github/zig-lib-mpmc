// #include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
struct wfring;
struct wfring_state;

void wqc_init(struct wfring *ring, size_t order);

void wqc_enque(struct wfring *ring, size_t order, size_t eidx, bool nonempty,
               struct wfring_state *state);

size_t wqc_deque(struct wfring *ring, size_t order, bool nonempty,
                 struct wfring_state *state);
