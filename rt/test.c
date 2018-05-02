#include <alloca.h>
#include <assert.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

void rt_3addiii(int *res, int a, int b)
{
    *res = a + b;
}

int rt_sub_int_int_int(int a, int b)
{
    return a - b;
}

void rt_2eqbii(bool *res, int a, int b)
{
    *res = a == b;
}

int rt_read_offs_int(void *data, int offset)
{
    return *(int*)(data + offset);
}

void *rt_write_offs_int(void *source, void *target, int size, int offset, int value)
{
    memcpy(target, source, size);
    *(int*)(target + offset) = value;
}

typedef void (*Closure)(void *ret, void *args);

void rt_2if(void *ret, bool test, Closure fn1, void *args1, Closure fn2, void *args2)
{
  if (test)
  {
    fn1(ret, args1);
  }
  else
  {
    fn2(ret, args2);
  }
}

int zero = 0;
int one = 1;

/*
 * int ack(int m, int n) = if(eq(m, 0), closure<ack_ret1>(n), closure<ack_rest1>(m, n))
 * int ack_ret1(int n) = add(n, 1)
 * int ack_rest1(int m, int n) = if(eq(n, 0), closure<ack_ret2>(m), closure<ack_rest2>(m, n))
 * int ack_ret2(int m) = sub(m, 1)
 * int ack_rest2(int m, int n) = ack(sub(m, 1), ack(m, sub(n, 1)))
 */

struct ack_frame
{
  int m;
  int n;
};

void ack(void *ret, void *argsp);

struct ack_ret2_frame
{
  int m;
};

void ack_ret2(void *ret, void *argsp)
{
  int temp = rt_sub_int_int_int(rt_read_offs_int(argsp, offsetof(struct ack_ret2_frame, m)), one);
  struct ack_frame callframe = { .m = temp, .n = one };
  ack((int*) ret, &callframe);
}

struct ack_rest2_frame
{
  int m;
  int n;
};

void ack_rest2(void *ret, void *argsp)
{
  struct ack_rest2_frame *args = (struct ack_rest2_frame *) argsp;
  int temp1, temp2, temp3;
  rt_3subiii(&temp1, args->n, one);
  struct ack_frame callframe1 = { .m = args->m, .n = temp1 };
  ack(&temp2, &callframe1);
  rt_3subiii(&temp3, args->m, one);
  struct ack_frame callframe2 = { .m = temp3, .n = temp2 };
  ack(ret, &callframe2);
}

struct ack_ret1_frame
{
  int n;
};

void ack_ret1(void *ret, void *argsp)
{
  struct ack_ret1_frame *args = (struct ack_ret1_frame *) argsp;
  rt_3addiii((int*) ret, args->n, one);
}

struct ack_rest1_frame
{
  int m;
  int n;
};

void ack_rest1(void *ret, void *argsp)
{
  struct ack_rest1_frame *args = (struct ack_rest1_frame *) argsp;
  bool temp;
  rt_2eqbii(&temp, args->n, zero);
  struct ack_ret2_frame frame1 = { .m = args->m };
  struct ack_rest2_frame frame2 = { .m = args->m, .n = args->n };
  rt_2if(ret, temp, &ack_ret2, &frame1, &ack_rest2, &frame2);
}

void ack(void *ret, void *argsp)
{
  struct ack_frame *args = (struct ack_frame *) argsp;
  bool temp;
  rt_2eqbii(&temp, args->m, zero);
  struct ack_ret1_frame frame1 = { .n = args->n };
  struct ack_rest1_frame frame2 = { .m = args->m, .n = args->n };
  rt_2if(ret, temp, &ack_ret1, &frame1, &ack_rest1, &frame2);
}

int wrap_ack(int m, int n)
{
  int ret;
  struct ack_frame frame = {
    .m = m,
    .n = n
  };
  ack(&ret, &frame);
  return ret;
}

int main(int argc, const char *argv[])
{
  for (int i = 0; i < 10; ++i)
  {
    printf("ack(3, 7) = %i\n", wrap_ack(3, 7));
  }
}
