package gk;

import Rj.C2732n;
import Rj.C2765z;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import sp.aicoin_kline.chart.data.EstimatedLiqVpcRecord;
import sp.aicoin_kline.chart.data.EstimatedLiqVpcTimePoints;

/* JADX INFO: loaded from: classes7.dex */
public final class V extends AbstractC7467h0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public LinkedHashMap f96485A;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public EstimatedLiqVpcTimePoints f96486t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public Map f96487u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final LinkedHashMap f96488v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final HashMap f96489w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public double f96490x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public double f96491y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public EstimatedLiqVpcTimePoints f96492z;

    public V(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
        this.f96488v = new LinkedHashMap();
        this.f96489w = new HashMap();
        this.f96490x = Double.NaN;
        this.f96491y = Double.NaN;
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        List listA;
        EstimatedLiqVpcTimePoints estimatedLiqVpcTimePointsF = sVar.q().F();
        this.f96492z = estimatedLiqVpcTimePointsF;
        if (estimatedLiqVpcTimePointsF == null) {
            this.f96485A = null;
            this.f96488v.clear();
            this.f96489w.clear();
            this.f96490x = Double.NaN;
            this.f96491y = Double.NaN;
            this.f96486t = null;
            this.f96487u = null;
            return;
        }
        Map<String, List<EstimatedLiqVpcRecord>> values = estimatedLiqVpcTimePointsF.getValues();
        if (estimatedLiqVpcTimePointsF == this.f96486t && values == this.f96487u && this.f96485A != null) {
            return;
        }
        Map<String, List<EstimatedLiqVpcRecord>> values2 = estimatedLiqVpcTimePointsF.getValues();
        if (values2.isEmpty()) {
            this.f96485A = null;
            this.f96488v.clear();
            this.f96489w.clear();
            this.f96490x = Double.NaN;
            this.f96491y = Double.NaN;
            this.f96486t = estimatedLiqVpcTimePointsF;
            this.f96487u = values;
            return;
        }
        Qf.p pVarB = Sj.c.f20766a.b(values2);
        double dDoubleValue = ((Number) pVarB.a()).doubleValue();
        double dDoubleValue2 = ((Number) pVarB.b()).doubleValue();
        boolean z10 = true;
        boolean z11 = this.f96488v.isEmpty() || this.f96489w.isEmpty() || dDoubleValue != this.f96490x || dDoubleValue2 != this.f96491y;
        if (!z11) {
            Set setKeySet = this.f96489w.keySet();
            if (!(setKeySet instanceof Collection) || !setKeySet.isEmpty()) {
                Iterator it = setKeySet.iterator();
                do {
                    if (!it.hasNext()) {
                        z10 = false;
                        break;
                    }
                } while (values2.containsKey((String) it.next()));
            } else {
                z10 = false;
                break;
            }
        } else {
            z10 = z11;
        }
        LinkedHashMap linkedHashMap = new LinkedHashMap(values2.size());
        for (Map.Entry<String, List<EstimatedLiqVpcRecord>> entry : values2.entrySet()) {
            String key = entry.getKey();
            List<EstimatedLiqVpcRecord> value = entry.getValue();
            if (z10) {
                listA = Sj.c.f20766a.a(value, dDoubleValue, dDoubleValue2);
            } else if (((List) this.f96489w.get(key)) != value) {
                listA = Sj.c.f20766a.a(value, dDoubleValue, dDoubleValue2);
            } else {
                listA = (List) this.f96488v.get(key);
                if (listA == null) {
                    listA = Sj.c.f20766a.a(value, dDoubleValue, dDoubleValue2);
                }
            }
            linkedHashMap.put(key, listA);
        }
        this.f96488v.clear();
        this.f96488v.putAll(linkedHashMap);
        this.f96489w.clear();
        for (Map.Entry<String, List<EstimatedLiqVpcRecord>> entry2 : values2.entrySet()) {
            this.f96489w.put(entry2.getKey(), entry2.getValue());
        }
        this.f96490x = dDoubleValue;
        this.f96491y = dDoubleValue2;
        this.f96485A = linkedHashMap;
        this.f96486t = estimatedLiqVpcTimePointsF;
        this.f96487u = values;
    }

    public final Map D() {
        return this.f96485A;
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
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
}
