#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

struct lfring;
extern const size_t SQC_EMPTY_DEQUEUE;
size_t sqc_size(size_t order);
void sqc_init(struct lfring *ring, size_t order);
bool sqc_enqueue(struct lfring *ring, size_t order, size_t val);
size_t sqc_dequeue(struct lfring *ring, size_t order);