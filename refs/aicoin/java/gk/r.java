package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.AIWinRateItem;

/* JADX INFO: loaded from: classes7.dex */
public final class r extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final sp.aicoin_kline.core.indicator.config.F f96550n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final ArrayList f96551o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public Map f96552p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public int f96553q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public int f96554r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public double[] f96555s;

    public r(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str);
        this.f96550n = f10;
        this.f96551o = new ArrayList();
        this.f96552p = Sf.N.j();
        this.f96553q = -1;
        this.f96554r = -1;
        this.f96555s = new double[0];
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Sj.b bVarD;
        double[] dArr2;
        Sj.a aVarC;
        y1 y1VarM;
        C2765z c2765zH = h().b().h(c());
        if (c2765zH == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        Sj.a aVarC2 = c2765zH.C();
        if (aVarC2.size() <= 0 || (bVarD = (Sj.b) Sf.z.r0(aVarC2, i10)) == null) {
            return;
        }
        if (i10 == iD) {
            bVarD = nk.c.f134195a.d(bVarD);
        }
        C2765z c2765zD = h().d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null || (y1VarM = h().b().m(c())) == null) {
            dArr2 = new double[]{Double.MAX_VALUE, -1.7976931348623157E308d};
        } else {
            double[] dArr3 = {Double.MAX_VALUE, -1.7976931348623157E308d};
            int iR = y1VarM.r();
            int iQ = y1VarM.q();
            if (this.f96553q == iR && this.f96554r == iQ) {
                dArr2 = this.f96555s;
            } else {
                this.f96553q = iR;
                this.f96554r = iQ;
                while (iR < iQ) {
                    Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, iR);
                    double dC = bVar != null ? bVar.c() : 0.0d;
                    double dB = bVar != null ? bVar.b() : 0.0d;
                    if (!Double.isNaN(dC)) {
                        dArr3[0] = Math.min(dC, dArr3[0]);
                    }
                    if (!Double.isNaN(dB)) {
                        dArr3[1] = Math.max(dB, dArr3[1]);
                    }
                    iR++;
                }
                this.f96555s = dArr3;
                dArr2 = dArr3;
            }
        }
        double d10 = dArr2[1] - dArr2[0];
        double d11 = d10 >= 0.0d ? d10 : 0.0d;
        Xj.a.a(12.0f);
        double d12 = d11 * 0.1d;
        dArr[0] = bVarD.c() + d12;
        dArr[1] = bVarD.b() - d12;
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        C2765z c2765zQ = sVar.q();
        if (c2765zQ.B() < 1) {
            return;
        }
        this.f96551o.clear();
        this.f96551o.addAll(c2765zQ.Z());
        ArrayList arrayList = this.f96551o;
        LinkedHashMap linkedHashMap = new LinkedHashMap();
        for (Object obj : arrayList) {
            String signal_type = ((AIWinRateItem) obj).getSignal_type();
            Object arrayList2 = linkedHashMap.get(signal_type);
            if (arrayList2 == null) {
                arrayList2 = new ArrayList();
                linkedHashMap.put(signal_type, arrayList2);
            }
            ((List) arrayList2).add(obj);
        }
        this.f96552p = linkedHashMap;
    }

    public final List s() {
        return this.f96551o;
    }

    public final boolean t(AIWinRateItem aIWinRateItem) {
        AIWinRateItem aIWinRateItem2;
        List list = (List) this.f96552p.get(aIWinRateItem.getSignal_type());
        return list != null && (aIWinRateItem2 = (AIWinRateItem) Sf.z.D0(list)) != null && AbstractC7609s.f(aIWinRateItem2.getId(), aIWinRateItem.getId()) && aIWinRateItem2.getState() == aIWinRateItem.getState();
    }
}
