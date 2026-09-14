package gk;

import Rj.C2732n;
import Rj.y1;
import Sf.AbstractC2801o;
import Sf.AbstractC2803q;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class U0 extends W {
    public U0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    @Override // gk.W
    public String D() {
        return "tvolume";
    }

    @Override // gk.W
    public List E() {
        return AbstractC2803q.e("volume");
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        y1 y1VarZ = z();
        if (y1VarZ == null) {
            return;
        }
        dArr[0] = Double.MAX_VALUE;
        dArr[1] = -1.7976931348623157E308d;
        long jH = y1VarZ.H(i10);
        double[][] dArrV = v();
        ArrayList arrayList = new ArrayList();
        for (double[] dArr2 : dArrV) {
            if (nk.z.b(dArr2, AbstractC2801o.w0(y(), Long.valueOf(jH)))) {
                arrayList.add(dArr2);
            }
        }
        if (arrayList.isEmpty()) {
            dArr[0] = Double.NaN;
            dArr[1] = Double.NaN;
            return;
        }
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(arrayList, 10));
        Iterator it = arrayList.iterator();
        while (it.hasNext()) {
            arrayList2.add(Double.valueOf(((double[]) it.next())[AbstractC2801o.w0(y(), Long.valueOf(y1VarZ.H(i10)))]));
        }
        Iterator it2 = arrayList2.iterator();
        while (it2.hasNext()) {
            double dDoubleValue = ((Number) it2.next()).doubleValue();
            dArr[0] = 0.0d;
            if (!Double.isNaN(dDoubleValue) && dDoubleValue > dArr[1]) {
                dArr[1] = dDoubleValue;
            }
        }
    }
}
