package Rj;

/* JADX INFO: loaded from: classes7.dex */
public class V extends AbstractC2759w0 {
    public V(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2759w0
    public void U(int i10) {
        p().clear();
        if (z() <= 0.0d) {
            return;
        }
        if (i10 - (w() + x()) < 1) {
            return;
        }
        int iO = O(10.0d);
        double dCeil = Math.ceil(v() / 10.0d) * 10.0d;
        if (dCeil == 0.0d) {
            dCeil = 0.0d;
        }
        if ((iO << 2) < Xj.a.d(24)) {
            if ((iO << 1) < 8) {
                return;
            }
            do {
                if (dCeil == 20.0d || dCeil == 80.0d) {
                    p().add(Double.valueOf(dCeil));
                }
                dCeil += 10.0d;
            } while (dCeil < u());
            return;
        }
        do {
            if (iO < Xj.a.d(6)) {
                if (dCeil == 20.0d || dCeil == 50.0d || dCeil == 80.0d) {
                    p().add(Double.valueOf(dCeil));
                }
            } else if (dCeil == 0.0d || dCeil == 20.0d || dCeil == 50.0d || dCeil == 80.0d || dCeil == 100.0d) {
                p().add(Double.valueOf(dCeil));
            }
            dCeil += 10.0d;
        } while (dCeil < u());
    }
}
