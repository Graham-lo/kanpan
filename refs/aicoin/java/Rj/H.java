package Rj;

import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class H {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final H f19133a = new H();

    public final int a(List list, float f10, float f11, float f12) {
        if (list.isEmpty() || f11 <= 0.0f) {
            return -1;
        }
        return p292ng.i.p((int) ((f12 + f10) / f11), 0, Sf.r.p(list));
    }

    public final long b(List list, float f10, float f11, float f12) {
        int iA = a(list, f10, f11, f12);
        if (iA < 0) {
            return 0L;
        }
        return ((Sj.b) list.get(iA)).e();
    }

    /* JADX WARN: Code duplicated, block: B:45:0x0086  */
    /* JADX WARN: Code duplicated, block: B:74:0x0105  */
    /* JADX WARN: Code duplicated, block: B:75:0x0107  */
    /* JADX WARN: Code duplicated, block: B:94:0x016d  */
    public final float c(List list, long j10, float f10) {
        int i10;
        long j11;
        float f11;
        Float fValueOf;
        long jLongValue;
        long j12;
        long jMin;
        long jLongValue2;
        float fFloor;
        if (list.isEmpty() || f10 <= 0.0f) {
            return -1.0f;
        }
        int size = list.size();
        int i11 = 0;
        while (true) {
            i10 = -1;
            if (i11 >= size) {
                i11 = -1;
                break;
            }
            if (!((Sj.b) list.get(i11)).g()) {
                break;
            }
            i11++;
        }
        int size2 = list.size() - 1;
        if (size2 >= 0) {
            while (true) {
                int i12 = size2 - 1;
                if (!((Sj.b) list.get(size2)).g()) {
                    i10 = size2;
                    break;
                }
                if (i12 < 0) {
                    break;
                }
                size2 = i12;
            }
        }
        if (i11 < 0 || i10 < i11) {
            return -1.0f;
        }
        long jE = ((Sj.b) list.get(i11)).e();
        long j13 = 0;
        if (j10 <= 0 || jE <= 0) {
            j11 = j10;
        } else {
            boolean z10 = jE >= 1000000000000L;
            boolean z11 = j10 >= 1000000000000L;
            if (z10 && !z11) {
                j11 = 1000 * j10;
            } else if (z10 || !z11) {
                j11 = j10;
            } else {
                j11 = j10 / 1000;
            }
        }
        if (i11 >= 0 && i10 >= i11 && i10 < list.size()) {
            long jE2 = ((Sj.b) list.get(i11)).e();
            if (j11 >= jE2) {
                f11 = -1.0f;
                long jE3 = ((Sj.b) list.get(i10)).e();
                if (j11 <= jE3) {
                    int i13 = i11;
                    int i14 = i10;
                    while (true) {
                        if (i13 > i14) {
                            fValueOf = Float.valueOf(p292ng.i.p(i13 - 1, i11, i10));
                            break;
                        }
                        int i15 = (i13 + i14) >>> 1;
                        long jE4 = ((Sj.b) list.get(i15)).e();
                        if (jE4 >= j11) {
                            if (jE4 <= j11) {
                                fValueOf = Float.valueOf(i15);
                                break;
                            }
                            i14 = i15 - 1;
                        } else {
                            i13 = i15 + 1;
                        }
                    }
                } else {
                    if (i10 - i11 < 1) {
                        jLongValue = 0;
                    } else {
                        long jE5 = ((Sj.b) list.get(i10)).e();
                        int iMax = Math.max(i11, i10 - 64);
                        int i16 = i10 - 1;
                        long jMin2 = Long.MAX_VALUE;
                        if (iMax <= i16) {
                            while (true) {
                                long jE6 = ((Sj.b) list.get(i16)).e();
                                long j14 = jE5 - jE6;
                                if (j14 > 0) {
                                    jMin2 = Math.min(jMin2, j14);
                                }
                                if (i16 == iMax) {
                                    break;
                                }
                                i16--;
                                jE5 = jE6;
                            }
                        }
                        Long lValueOf = Long.valueOf(jMin2);
                        if (jMin2 == Long.MAX_VALUE) {
                            lValueOf = null;
                        }
                        if (lValueOf != null) {
                            jLongValue = lValueOf.longValue();
                        } else {
                            jLongValue = 0;
                        }
                    }
                    fValueOf = Float.valueOf(jLongValue <= 0 ? i10 : (float) (Math.floor((j11 - jE3) / jLongValue) + ((double) i10)));
                }
            } else {
                if (i10 - i11 < 1) {
                    j12 = 0;
                    f11 = -1.0f;
                } else {
                    long jE7 = ((Sj.b) list.get(i11)).e();
                    int iMin = Math.min(i10, i11 + 64);
                    int i17 = i11 + 1;
                    if (i17 <= iMin) {
                        jMin = Long.MAX_VALUE;
                        f11 = -1.0f;
                        while (true) {
                            long jE8 = ((Sj.b) list.get(i17)).e();
                            j12 = j13;
                            long j15 = jE8 - jE7;
                            if (j15 > j12) {
                                jMin = Math.min(jMin, j15);
                            }
                            if (i17 == iMin) {
                                break;
                            }
                            i17++;
                            jE7 = jE8;
                            j13 = j12;
                        }
                    } else {
                        j12 = 0;
                        f11 = -1.0f;
                        jMin = Long.MAX_VALUE;
                    }
                    Long lValueOf2 = jMin == Long.MAX_VALUE ? null : Long.valueOf(jMin);
                    if (lValueOf2 != null) {
                        jLongValue2 = lValueOf2.longValue();
                    }
                    if (jLongValue2 <= j12) {
                        fFloor = i11;
                    } else {
                        fFloor = (float) (Math.floor((j11 - jE2) / jLongValue2) + ((double) i11));
                    }
                    fValueOf = Float.valueOf(fFloor);
                }
                jLongValue2 = j12;
                if (jLongValue2 <= j12) {
                    fFloor = i11;
                } else {
                    fFloor = (float) (Math.floor((j11 - jE2) / jLongValue2) + ((double) i11));
                }
                fValueOf = Float.valueOf(fFloor);
            }
        } else {
            f11 = -1.0f;
            fValueOf = null;
        }
        if (fValueOf != null) {
            return (f10 / 2.0f) + (fValueOf.floatValue() * f10);
        }
        return f11;
    }
}
