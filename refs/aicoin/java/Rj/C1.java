package Rj;

import android.graphics.Paint;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public final class C1 extends AbstractC2721j0 {

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public static final a f19062k = new a(null);

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final C2732n f19063g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final Paint f19064h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public float f19065i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public List f19066j;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C1() {
        this(null, null, 3, null);
    }

    public C1(C2732n c2732n, String str) {
        super(str);
        this.f19063g = c2732n;
        this.f19064h = new Paint();
        this.f19066j = new ArrayList();
    }

    public /* synthetic */ C1(C2732n c2732n, String str, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? null : c2732n, (i10 & 2) != 0 ? "" : str);
    }

    /* JADX WARN: Code duplicated, block: B:9:0x0021 A[PHI: r0
      0x0021: PHI (r0v3 java.text.SimpleDateFormat) = (r0v2 java.text.SimpleDateFormat), (r0v4 java.text.SimpleDateFormat) binds: [B:5:0x0010, B:7:0x001a] A[DONT_GENERATE, DONT_INLINE]] */
    public final void g(float f10, long j10, SimpleDateFormat simpleDateFormat) {
        if (nk.w.u(j10)) {
            nk.w wVar = nk.w.f134250a;
            SimpleDateFormat simpleDateFormatG = wVar.g();
            if (nk.w.q(j10)) {
                simpleDateFormatG = wVar.j();
                if (nk.w.v(j10)) {
                    simpleDateFormat = wVar.o();
                } else {
                    simpleDateFormat = simpleDateFormatG;
                }
            } else {
                simpleDateFormat = simpleDateFormatG;
            }
        }
        this.f19066j.add(new A1(f10, j10, simpleDateFormat));
    }

    public final List h() {
        return this.f19066j;
    }

    public final void i() {
        this.f19064h.setTextSize(nk.l.o(2, 9.0f));
        this.f19065i = nk.l.o(1, 16.0f) + this.f19064h.measureText("yyyy年M月");
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void j() {
        C2741q c2741qB;
        y1 y1VarM;
        C2765z c2765zD;
        Sj.a aVarC;
        long j10;
        SimpleDateFormat simpleDateFormatG;
        SimpleDateFormat simpleDateFormatJ;
        SimpleDateFormat simpleDateFormatJ2;
        C2732n c2732n = this.f19063g;
        if (c2732n == null || (c2741qB = c2732n.b()) == null || (y1VarM = c2741qB.m("ds0")) == null || (c2765zD = this.f19063g.d()) == null || (aVarC = c2765zD.C()) == null || aVarC.size() < 2) {
            return;
        }
        int i10 = 0;
        long jE = ((Sj.b) aVarC.get(1)).e() - ((Sj.b) aVarC.get(0)).e();
        int length = nk.w.f134250a.n().length;
        int i11 = 0;
        while (i11 < length && jE >= nk.w.f134250a.n()[i11]) {
            i11++;
        }
        long j11 = 0;
        if (jE != 0) {
            while (true) {
                if (i11 > 22) {
                    j10 = j11;
                    break;
                }
                nk.w wVar = nk.w.f134250a;
                if (wVar.n()[i11] % jE == j11) {
                    j10 = j11;
                    if (y1VarM.u() * (wVar.n()[i11] / jE) > ((double) this.f19065i) * 1.6d) {
                        break;
                    }
                } else {
                    j10 = j11;
                }
                i11++;
                j11 = j10;
            }
            while (i11 < length) {
                nk.w wVar2 = nk.w.f134250a;
                if (jE < wVar2.n()[i11]) {
                    if (y1VarM.u() * (wVar2.n()[i11] / jE) > ((double) this.f19065i) * 1.6d) {
                        break;
                    }
                }
                i11++;
            }
        } else {
            j10 = 0;
        }
        int i12 = i11;
        int iR = y1VarM.r();
        int iY = y1VarM.y();
        float fU = y1VarM.u();
        float fU2 = (y1VarM.u() / 2) - y1VarM.J();
        this.f19066j.clear();
        int i13 = iR;
        while (i13 < iY) {
            long jE2 = ((Sj.b) aVarC.get(i13)).e();
            float f10 = ((i13 - iR) * fU) + fU2;
            if (i12 < 5) {
                simpleDateFormatG = nk.w.f134250a.l();
            } else if (i12 < 15) {
                simpleDateFormatG = nk.w.f134250a.m();
            } else {
                nk.w wVar3 = nk.w.f134250a;
                simpleDateFormatG = i12 < wVar3.n().length ? wVar3.g() : wVar3.j();
            }
            SimpleDateFormat simpleDateFormatG2 = simpleDateFormatG;
            long jE3 = ((Sj.b) aVarC.get(i10)).e();
            if (i12 < 0 || i12 >= 5) {
                if (5 > i12 || i12 >= 15) {
                    if (15 > i12 || i12 >= 23) {
                        long jI = jE3;
                        if (23 > i12 || i12 >= 28) {
                            fU2 = fU2;
                            aVarC = aVarC;
                            if (1382400000 <= jE && jE < 10368000001L) {
                                SimpleDateFormat simpleDateFormatO = nk.w.f134250a.o();
                                if (nk.w.f(jE2, i12) && nk.w.v(jE2)) {
                                    g(f10, jE2, simpleDateFormatO);
                                }
                            } else if (18144000000L > jE || jE >= 62208000001L) {
                                if (jE == 172800000 || jE == 259200000 || jE == 432000000 || jE == 604800000) {
                                    nk.w wVar4 = nk.w.f134250a;
                                    SimpleDateFormat simpleDateFormatP = wVar4.p();
                                    if (nk.w.v(jE2) && nk.w.q(jE2)) {
                                        simpleDateFormatP = wVar4.o();
                                    }
                                    if (nk.w.c(jE2, i12, (int) (jE / 86400000))) {
                                        g(f10, jE2, simpleDateFormatP);
                                    }
                                }
                            } else if (nk.w.f(jE2, i12)) {
                                g(f10, jE2, nk.w.f134250a.o());
                            }
                        } else if (jE == 86400000) {
                            if (nk.w.e(jE2, i12, 0, 4, null) && nk.w.q(jE2)) {
                                g(f10, jE2, nk.w.f134250a.j());
                            }
                        } else if (jE == 14400000) {
                            if (nk.w.e(jE2, i12, 0, 4, null) && nk.w.t(jE2, false)) {
                                g(f10, jE2, nk.w.f134250a.j());
                            }
                        } else if (jE == 21600000) {
                            if (!nk.w.x(jI, jE)) {
                                jI = (((26 - ((long) nk.w.i(jI))) / 6) * nk.w.f134250a.n()[12]) + jI;
                            }
                            if (nk.w.a(jI, jE2, i12)) {
                                g(f10, jE2, nk.w.f134250a.g());
                            }
                        } else {
                            fU2 = fU2;
                            aVarC = aVarC;
                            if (jE == 43200000) {
                                if (!nk.w.x(jI, jE)) {
                                    jI += nk.w.f134250a.n()[14];
                                }
                                if (nk.w.a(jI, jE2, i12)) {
                                    g(f10, jE2, simpleDateFormatG2);
                                }
                            } else if (jE == 604800000) {
                                if (nk.w.c(jE2, i12, 7)) {
                                    nk.w wVar5 = nk.w.f134250a;
                                    SimpleDateFormat simpleDateFormatP2 = wVar5.p();
                                    if (nk.w.v(jE2) && nk.w.q(jE2)) {
                                        simpleDateFormatP2 = wVar5.o();
                                    }
                                    g(f10, jE2, simpleDateFormatP2);
                                }
                            } else if (jE == 172800000 || jE == 259200000 || jE == 432000000) {
                                if (nk.w.d(jI, jE2, i12)) {
                                    if (nk.w.q(jE2)) {
                                        nk.w wVar6 = nk.w.f134250a;
                                        simpleDateFormatJ = wVar6.j();
                                        if (nk.w.r(jE2)) {
                                            simpleDateFormatJ = wVar6.o();
                                        }
                                    } else {
                                        simpleDateFormatJ = simpleDateFormatG2;
                                    }
                                    g(f10, jE2, simpleDateFormatJ);
                                }
                            } else if (2419200000L <= jE && jE < 15552000001L && nk.w.e(jE2, i12, 0, 4, null)) {
                                if (nk.w.q(jE2)) {
                                    nk.w wVar7 = nk.w.f134250a;
                                    simpleDateFormatJ2 = wVar7.j();
                                    if (nk.w.r(jE2)) {
                                        simpleDateFormatJ2 = wVar7.o();
                                    }
                                } else {
                                    simpleDateFormatJ2 = simpleDateFormatG2;
                                }
                                g(f10, jE2, simpleDateFormatJ2);
                            }
                        }
                        i13++;
                        aVarC = aVarC;
                        fU2 = fU2;
                        i10 = 0;
                    } else if ((j10 <= jE && jE < 1800001) || jE == 3600000 || jE == 7200000 || jE == 14400000) {
                        nk.w wVar8 = nk.w.f134250a;
                        if ((jE2 + 28800000) % wVar8.n()[i12] == j10) {
                            g(f10, jE2, nk.w.w(jE2, i12) ? wVar8.g() : simpleDateFormatG2);
                        }
                    } else if (jE == 10800000 || jE == 21600000 || jE == 43200000) {
                        nk.w wVar9 = nk.w.f134250a;
                        if (jE2 % wVar9.n()[i12] == j10 || (jE2 + 28800000) % wVar9.n()[i12] == j10) {
                            g(f10, jE2, nk.w.w(jE2, i12) ? wVar9.g() : simpleDateFormatG2);
                        }
                    } else if (nk.w.b(jE3, jE, jE2, i12)) {
                        g(f10, jE2, simpleDateFormatG2);
                    }
                } else if (jE == 10800000) {
                    nk.w wVar10 = nk.w.f134250a;
                    if (jE2 % wVar10.n()[i12] == j10 || (jE2 + 28800000) % wVar10.n()[i12] == j10) {
                        if (nk.w.w(jE2, i12)) {
                            simpleDateFormatG2 = wVar10.g();
                        }
                        g(f10, jE2, simpleDateFormatG2);
                    }
                } else if (jE == 21600000 || jE == 43200000) {
                    nk.w wVar11 = nk.w.f134250a;
                    if (jE2 % wVar11.n()[i12] == j10) {
                        if (nk.w.w(jE2, i12)) {
                            simpleDateFormatG2 = wVar11.g();
                        }
                        g(f10, jE2, simpleDateFormatG2);
                    }
                } else {
                    nk.w wVar12 = nk.w.f134250a;
                    if ((jE2 + 28800000) % wVar12.n()[i12] == j10) {
                        if (nk.w.w(jE2, i12)) {
                            simpleDateFormatG2 = wVar12.g();
                        }
                        g(f10, jE2, simpleDateFormatG2);
                    }
                }
            } else if (jE2 % nk.w.f134250a.n()[i12] == j10) {
                this.f19066j.add(new A1(f10, jE2, simpleDateFormatG2));
            }
            fU2 = fU2;
            aVarC = aVarC;
            i13++;
            aVarC = aVarC;
            fU2 = fU2;
            i10 = 0;
        }
    }
}
