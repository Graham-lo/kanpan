package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import Sf.AbstractC2801o;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.chart.data.AISRLData;
import sp.aicoin_kline.chart.data.AISRLItem;

/* JADX INFO: renamed from: gk.p, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7482p extends AbstractC2755v {

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public static final a f96541r = new a(null);

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final sp.aicoin_kline.core.indicator.config.F f96542n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f96543o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public y1 f96544p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public volatile C7480o f96545q;

    /* JADX INFO: renamed from: gk.p$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C7482p(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str);
        this.f96542n = f10;
        this.f96545q = new C7480o(null, 0.0d, 3, null);
        this.f96543o = f10.r().length;
        this.f96544p = c2732n.b().m("ds0");
    }

    public static List s(List list, double d10, boolean z10) {
        if (list.isEmpty() || d10 <= 0.0d) {
            return new ArrayList();
        }
        LinkedHashMap linkedHashMap = new LinkedHashMap();
        Iterator it = list.iterator();
        while (it.hasNext()) {
            AISRLItem aISRLItem = (AISRLItem) it.next();
            if (aISRLItem.getPrice() > 0.0d && aISRLItem.getAmount() != 0.0d) {
                double price = aISRLItem.getPrice() / d10;
                double dCeil = (z10 ? Math.ceil(price - 1.0E-12d) : Math.floor(price + 1.0E-12d)) * d10;
                Double dValueOf = Double.valueOf(dCeil);
                Double d11 = (Double) linkedHashMap.get(Double.valueOf(dCeil));
                linkedHashMap.put(dValueOf, Double.valueOf(aISRLItem.getAmount() + (d11 != null ? d11.doubleValue() : 0.0d)));
            }
        }
        List<Map.Entry> listD1 = Sf.z.d1(linkedHashMap.entrySet(), new C7484q());
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listD1, 10));
        for (Map.Entry entry : listD1) {
            arrayList.add(new AISRLItem(((Double) entry.getKey()).doubleValue(), ((Double) entry.getValue()).doubleValue(), null, 0, 12, null));
        }
        return Sf.z.u1(arrayList);
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Sj.b bVarD;
        C2765z c2765zH = h().b().h(c());
        if (c2765zH == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        Sj.a aVarC = c2765zH.C();
        if (aVarC.size() <= 0 || (bVarD = (Sj.b) Sf.z.r0(aVarC, i10)) == null) {
            return;
        }
        if (i10 == iD) {
            bVarD = nk.c.f134195a.d(bVarD);
        }
        dArr[0] = bVarD.c();
        dArr[1] = bVarD.b();
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        w(sVar);
    }

    public final AISRLData t() {
        return this.f96545q.a();
    }

    public final C7480o u() {
        return this.f96545q;
    }

    public final int v(boolean z10) {
        int i10 = !z10 ? 1 : 0;
        ek.I i11 = (ek.I) AbstractC2801o.r0(this.f96542n.r(), i10);
        if (i11 == null || !i11.b()) {
            return 0;
        }
        ek.w wVar = (ek.w) AbstractC2801o.r0(this.f96542n.l(), i10);
        if (wVar != null) {
            return p292ng.i.p(wVar.g(), 1, 5);
        }
        return 1;
    }

    /* JADX WARN: Code duplicated, block: B:51:0x012f  */
    public final void w(dk.s sVar) {
        double dDoubleValue;
        C7480o c7480o;
        double d10;
        double dDoubleValue2;
        int i10;
        List list;
        double dV = sVar.q().V();
        Double dValueOf = Double.valueOf(dV);
        if (dV <= 0.0d) {
            dValueOf = null;
        }
        double dDoubleValue3 = dValueOf != null ? dValueOf.doubleValue() : sVar.y();
        int iB = nk.n.f134230a.b();
        AISRLData aISRLDataZ = sVar.q().z();
        int i11 = 0;
        ek.I i12 = (ek.I) AbstractC2801o.r0(this.f96542n.r(), 0);
        boolean z10 = i12 != null && i12.b();
        ek.I i13 = (ek.I) AbstractC2801o.r0(this.f96542n.r(), 1);
        boolean z11 = i13 != null && i13.b();
        if ((z10 || z11) && dDoubleValue3 != 0.0d) {
            List arrayList = new ArrayList();
            List arrayList2 = new ArrayList();
            double d11 = iB;
            if (dDoubleValue3 <= 0.0d) {
                dDoubleValue = 1.0d;
            } else {
                List listT = Sf.r.t(5, 2, 1);
                int i14 = 8;
                Double d12 = null;
                while (true) {
                    if (-9 >= i14) {
                        d10 = d11;
                        dDoubleValue2 = 1.0E-8d;
                        break;
                    }
                    int size = listT.size();
                    while (true) {
                        if (i11 >= size) {
                            d10 = d11;
                            i10 = i14;
                            list = listT;
                            break;
                        }
                        d10 = d11;
                        list = listT;
                        i10 = i14;
                        Double dN = Ah.v.n(nk.s.f134244a.a(Math.pow(10.0d, i14) * ((Number) listT.get(i11)).doubleValue(), 8));
                        if (dN == null) {
                            break;
                        }
                        if (dN.doubleValue() / dDoubleValue3 <= 0.02d) {
                            d12 = dN;
                            break;
                        }
                        i11++;
                        listT = list;
                        d11 = d10;
                        i14 = i10;
                    }
                    if (d12 != null) {
                        dDoubleValue2 = d12.doubleValue();
                        break;
                    }
                    i14 = i10 - 1;
                    listT = list;
                    d11 = d10;
                    i11 = 0;
                }
                double dMin = Math.min(Math.max((d10 * dDoubleValue2) / 9000.0d, dDoubleValue2 / 100.0d), 50.0d);
                Double dValueOf2 = dMin > 0.0d ? Double.valueOf(dMin) : null;
                if (dValueOf2 != null) {
                    dDoubleValue = dValueOf2.doubleValue();
                } else {
                    dDoubleValue = 1.0d;
                }
            }
            if (z10) {
                arrayList = s(aISRLDataZ.getAskList(), dDoubleValue, true);
            }
            if (z11) {
                arrayList2 = s(aISRLDataZ.getBidList(), dDoubleValue, false);
            }
            c7480o = new C7480o(new AISRLData(arrayList, arrayList2, aISRLDataZ.getAmountUnit()), dDoubleValue);
        } else {
            c7480o = new C7480o(null, 0.0d, 3, null);
        }
        this.f96545q = c7480o;
    }
}
