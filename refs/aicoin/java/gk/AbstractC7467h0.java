package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.y1;
import Sf.AbstractC2801o;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: renamed from: gk.h0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC7467h0 extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final sp.aicoin_kline.core.indicator.config.F f96511n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public boolean f96512o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public double[][] f96513p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public Long[] f96514q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f96515r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public y1 f96516s;

    public AbstractC7467h0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10, boolean z10) {
        super(c2732n, str);
        this.f96511n = f10;
        this.f96512o = z10;
        int length = f10.r().length;
        this.f96515r = length;
        double[][] dArr = new double[length][];
        for (int i10 = 0; i10 < length; i10++) {
            dArr[i10] = new double[0];
        }
        this.f96513p = dArr;
        this.f96514q = new Long[0];
    }

    public /* synthetic */ AbstractC7467h0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10, boolean z10, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this(c2732n, str, f10, (i10 & 8) != 0 ? false : z10);
    }

    public void A(dk.s sVar) {
    }

    public final void B() {
        int length = this.f96513p.length;
        for (int i10 = 0; i10 < length; i10++) {
            this.f96513p[i10] = new double[0];
        }
        this.f96514q = new Long[0];
        this.f96516s = h().b().m("ds0");
    }

    public final void C(Long[] lArr) {
        this.f96514q = lArr;
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        ArrayList arrayList;
        ArrayList arrayList2;
        dArr[0] = Double.MAX_VALUE;
        dArr[1] = -1.7976931348623157E308d;
        y1 y1Var = this.f96516s;
        if (y1Var == null) {
            return;
        }
        if (this.f96512o) {
            long jH = y1Var.H(i10);
            double[][] dArr2 = this.f96513p;
            arrayList = new ArrayList();
            for (double[] dArr3 : dArr2) {
                if (nk.z.b(dArr3, AbstractC2801o.w0(this.f96514q, Long.valueOf(jH)))) {
                    arrayList.add(dArr3);
                }
            }
        } else {
            double[][] dArr4 = this.f96513p;
            arrayList = new ArrayList();
            for (double[] dArr5 : dArr4) {
                if (nk.z.b(dArr5, i10)) {
                    arrayList.add(dArr5);
                }
            }
        }
        if (arrayList.isEmpty()) {
            dArr[0] = Double.NaN;
            dArr[1] = Double.NaN;
            return;
        }
        if (this.f96512o) {
            arrayList2 = new ArrayList(AbstractC2804s.y(arrayList, 10));
            Iterator it = arrayList.iterator();
            while (it.hasNext()) {
                arrayList2.add(Double.valueOf(((double[]) it.next())[AbstractC2801o.w0(this.f96514q, Long.valueOf(y1Var.H(i10)))]));
            }
        } else {
            arrayList2 = new ArrayList(AbstractC2804s.y(arrayList, 10));
            Iterator it2 = arrayList.iterator();
            while (it2.hasNext()) {
                arrayList2.add(Double.valueOf(((double[]) it2.next())[i10]));
            }
        }
        Iterator it3 = arrayList2.iterator();
        while (it3.hasNext()) {
            double dDoubleValue = ((Number) it3.next()).doubleValue();
            if (!Double.isNaN(dDoubleValue)) {
                if (dDoubleValue < dArr[0]) {
                    dArr[0] = dDoubleValue;
                }
                if (dDoubleValue > dArr[1]) {
                    dArr[1] = dDoubleValue;
                }
            }
        }
    }

    @Override // Rj.AbstractC2755v
    public final void q(dk.s sVar) {
        A(sVar);
    }

    public final void s(double[] dArr, int i10) {
        p292ng.e eVarA = i10 >= 0 ? p292ng.e.f134085d.a(AbstractC2801o.j0(dArr), 0, -1) : p292ng.e.f134085d.a(0, AbstractC2801o.j0(dArr), 1);
        int iK = eVarA.k();
        int iO = eVarA.o();
        int iQ = eVarA.q();
        if ((iQ <= 0 || iK > iO) && (iQ >= 0 || iO > iK)) {
            return;
        }
        while (true) {
            int i11 = iK + i10;
            double d10 = dArr[iK];
            dArr[iK] = Double.NaN;
            if (i11 <= AbstractC2801o.j0(dArr) && i11 >= 0) {
                dArr[i11] = d10;
            }
            if (iK == iO) {
                return;
            } else {
                iK += iQ;
            }
        }
    }

    public final double[] t(double[] dArr, int i10) {
        double[] dArrCopyOf = Arrays.copyOf(dArr, dArr.length);
        s(dArrCopyOf, i10);
        return dArrCopyOf;
    }

    public final boolean u() {
        return this.f96512o;
    }

    public final double[][] v() {
        return this.f96513p;
    }

    public final int w() {
        return this.f96515r;
    }

    public final sp.aicoin_kline.core.indicator.config.F x() {
        return this.f96511n;
    }

    public final Long[] y() {
        return this.f96514q;
    }

    public final y1 z() {
        return this.f96516s;
    }
}
