module radixsort;

import std.functional;
import std.traits;
import std.algorithm.mutation : swap;


/**
 * Sort array using radix sort.
 *
 * Radix sort is very fast algorithm for sorting small values using an integral
 * or floating point key. Sizes of 4 or 8 bytes are ideal. Bigger ones get
 * progressively slower as radix sort have to move every value same number of
 * times as number of bytes in the sorting key.
 * 
 * The result is guaranteed to be written in the array passed as the first argument.
 */
T[] radixsort(alias keyFun = "a", T)(T[] arr, T[] _tmparr) {
  assert(_tmparr.length >= arr.length, "The temporary array must be at least as long as the source array.");

  auto sourcePtr = arr.ptr;
  auto tmparr = _tmparr[0 .. arr.length];

  alias key = unaryFun!keyFun;
  alias keyType = ReturnType!((T t) => key(t));
  enum byteLen = keyType.sizeof;

  static assert (isIntegral!keyType || isFloatingPoint!keyType, "radixsort can sort only integral and floating point types.");

  union FloatBits { float f; uint i; }
  union DoubleBits { double f; ulong i; }

  static if (is(keyType == float)) {
    alias keyAsInt = (x) => FloatBits(key(x)).i;
  } else static if (is(keyType == double)) {
    alias keyAsInt = (x) => DoubleBits(key(x)).i;
  } else {
    alias keyAsInt = key;
  }

  int[256][byteLen] counts;
  int[256] offsets = void;

  // count byte histograms
  foreach (x; arr) {
    static foreach (b; 0 .. byteLen) {{
      uint c = (keyAsInt(x) >> (b * 8)) & 0xff;
      counts[b][c] += 1;
    }}
  }


  static if (isIntegral!keyType) {

    foreach (b; 0 .. byteLen) {
      if (canSkip(counts[b], arr.length)) continue;

      // this fixes offsets for negative integral keys
      int shift = (isSigned!keyType && b == byteLen-1) ? 128 : 0;
      alias wrap = (i) => ((i+256) % 256);

      offsets[shift] = 0;
      foreach (i; 1 .. 256) {
        i = wrap(i+shift);
        offsets[i] = counts[b][wrap(i-1)] + offsets[wrap(i-1)];
      }

      foreach (x; arr) {
        uint c = (keyAsInt(x) >> (b * 8)) & 0xff;
        tmparr.ptr[offsets[c]] = x;
        offsets[c]++;
      }

      swap(arr, tmparr);
    }


  } else static if (isFloatingPoint!keyType) {

    // all iterations but the last one
    foreach (b; 0 .. byteLen-1) {
      if (canSkip(counts[b], arr.length)) continue;

      offsets[0] = 0;
      foreach (i; 1 .. 256) {
        offsets[i] = counts[b][i-1] + offsets[i-1];
      }

      foreach (x; arr) {
        uint c = (keyAsInt(x) >> (b * 8)) & 0xff;
        tmparr.ptr[offsets[c]] = x;
        offsets[c]++;
      }

      swap(arr, tmparr);
    }

    // the last iteration needs to handle negative values
    foreach (b; byteLen-1 .. byteLen) {
      if (canSkip(counts[b], arr.length)) continue;

      offsets[255] = 0;
      foreach_reverse (i; 128 .. 255) {
        offsets[i] = counts[b][i+1] + offsets[i+1];
      }
      offsets[0] = counts[b][128] + offsets[128];
      foreach (i; 1 .. 128) {
        offsets[i] = counts[b][i-1] + offsets[i-1];
      }
      foreach_reverse (i; 128 .. 256) {
        offsets[i] += counts[b][i] - 1;
      }

      foreach (x; arr) {
        uint c = (keyAsInt(x) >> (b * 8)) & 0xff;
        tmparr.ptr[offsets[c]] = x;
        offsets[c] += (c >= 128) ? -1 : 1;
      }

      swap(arr, tmparr);
    }

  } else assert(0);

  // Sorted result is now in the memory originally pointed to by the tmparr
  // argument. Must be copied to the source array.
  if (arr.ptr != sourcePtr) {
    tmparr[] = arr[];
    return tmparr;
  }

  return arr;
}

private bool canSkip(ref int[256] cnts, ulong len) {
  foreach (c; cnts) {
    if (c == len) return true;
    if (c != 0) return false;
  }
  return false;
}



unittest {
  import std.algorithm;
  import std.random;
  import std.range;
  import std.conv;
  import std.meta;

  auto rnd = Random(1337);

  static foreach (T; AliasSeq!(ulong, long, uint, int, ushort, short, ubyte, byte, float, double)) {{
    foreach (i; 0 .. 10) {
      T[] arr = rnd.take(100+i).map!(x => cast(T)x).array;
      auto sorted = radixsort(arr, new T[arr.length]);
      assert(isSorted(sorted), sorted.to!string);
      assert(sorted.ptr == arr.ptr);
    }
  }}

  static foreach (T; AliasSeq!(float, double)) {{
    foreach (i; 0 .. 10) {
      T[] arr = iota(100+i).map!(x => rnd.uniform01!T - T(0.5)).array;
      auto sorted = radixsort(arr, new T[arr.length]);
      assert(isSorted(sorted), T.stringof ~ " " ~ sorted.to!string);
      assert(sorted.ptr == arr.ptr);
    }
  }}

  struct S2 { short key; short val; }
  struct D2 { double key; double val; }

  static foreach (T; AliasSeq!(S2, D2)) {{
    foreach (i; 0 .. 10) {
      T[] arr = rnd.take(100+i).map!(x => T(cast(typeof(T.key))x, 0)).array;
      auto sorted = radixsort!"a.key"(arr, new T[arr.length]);
      assert(isSorted!"a.key < b.key"(sorted), sorted.to!string);
      assert(sorted.ptr == arr.ptr);
    }
  }}
}
