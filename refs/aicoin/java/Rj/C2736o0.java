package Rj;

/* JADX INFO: renamed from: Rj.o0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2736o0 extends y1 {
    public C2736o0(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.y1
    public void K(float f10) {
        super.K(f10);
        c0(D());
    }

    @Override // Rj.y1
    public void U(float f10) {
        super.U(f10);
        c0(D());
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void c0(int i10) {
        U uK;
        C2765z c2765zH = k().b().h(c());
        if (c2765zH == null || (uK = k().b().k(c())) == null) {
            return;
        }
        Sj.a aVarC = c2765zH.C();
        if (i10 >= 0) {
            int i11 = 1;
            if (i10 > aVarC.size() - 1) {
                return;
            }
            Sj.b bVar = (Sj.b) aVarC.get(i10);
            int I10 = (I() / 2) + r();
            if (D() < I10) {
                i11 = 0;
            } else if (D() <= I10) {
                i11 = 2;
            }
            uK.y(bVar, i11);
        }
    }
}
