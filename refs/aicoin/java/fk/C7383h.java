package fk;

import Qf.InterfaceC2632j;
import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2738p;
import Rj.C2741q;
import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import gk.C7480o;
import gk.C7482p;
import java.util.ArrayList;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.chart.data.AISRLData;
import sp.aicoin_kline.chart.data.AISRLInfo;
import sp.aicoin_kline.chart.data.AISRLItem;

/* JADX INFO: renamed from: fk.h, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7383h extends AbstractC2744r0 {

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public static final a f95391s = new a(null);

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final nk.r f95392l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final InterfaceC2632j f95393m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95394n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95395o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public C2702d f95396p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public AbstractC2759w0 f95397q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public C7482p f95398r;

    /* JADX INFO: renamed from: fk.h$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C7383h(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95392l = new nk.r();
        this.f95393m = Qf.k.b(new C7382g(c2732n));
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.FILL_AND_STROKE);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        paint.setPathEffect(new DashPathEffect(new float[]{10.0f, 8.0f}, 0.0f));
        this.f95394n = new Paint(paint);
        this.f95395o = new Paint(paint);
    }

    public static final float v(C2732n c2732n) {
        return Math.max(20.0f, nk.u.a(c2732n.c(), 14.0f));
    }

    public static List w(List list, int i10, boolean z10, AbstractC2759w0 abstractC2759w0, double d10) {
        int iP = p292ng.i.p(i10, 0, 5);
        if (iP == 0 || list.isEmpty()) {
            return Sf.r.n();
        }
        Double dValueOf = Double.valueOf(d10);
        if (d10 <= 0.0d) {
            dValueOf = null;
        }
        double dDoubleValue = dValueOf != null ? dValueOf.doubleValue() : 0.0d;
        double dMin = Math.min(abstractC2759w0.v(), abstractC2759w0.u()) - dDoubleValue;
        double dMax = Math.max(abstractC2759w0.v(), abstractC2759w0.u()) + dDoubleValue;
        ArrayList arrayList = new ArrayList();
        for (Object obj : list) {
            AISRLItem aISRLItem = (AISRLItem) obj;
            if (aISRLItem.getAmount() != 0.0d && aISRLItem.getPrice() >= dMin && aISRLItem.getPrice() <= dMax) {
                arrayList.add(obj);
            }
        }
        List listI1 = Sf.z.i1(Sf.z.d1(arrayList, new C7385j()), iP);
        return z10 ? Sf.z.d1(listI1, new C7384i()) : Sf.z.d1(listI1, new C7386k());
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C7482p c7482p;
        C2702d c2702d;
        AbstractC2759w0 abstractC2759w0 = this.f95397q;
        if (abstractC2759w0 == null || (c7482p = this.f95398r) == null || (c2702d = this.f95396p) == null || abstractC2759w0.z() == 0.0d) {
            return;
        }
        nk.r.b bVarC = this.f95392l.c();
        bVarC.d();
        C7480o c7480oU = c7482p.u();
        AISRLData aISRLDataA = c7480oU.a();
        double dB = c7480oU.b();
        List listW = w(aISRLDataA.getAskList(), c7482p.v(true), true, abstractC2759w0, dB);
        List<AISRLItem> bidList = aISRLDataA.getBidList();
        int i10 = 0;
        List listW2 = w(bidList, c7482p.v(false), false, abstractC2759w0, dB);
        int i11 = 0;
        for (Object obj : listW) {
            int i12 = i11 + 1;
            if (i11 < 0) {
                Sf.r.x();
            }
            AISRLItem aISRLItemCopy$default = AISRLItem.copy$default((AISRLItem) obj, 0.0d, 0.0d, AISRLItem.SIDE_PRESSURE, i12, 3, null);
            float fU = c2702d.u();
            float fY = c2702d.y();
            float fS = abstractC2759w0.S(aISRLItemCopy$default.getPrice());
            canvas.drawLine(fU, fS, fY, fS, this.f95394n);
            float fFloatValue = fS - ((Number) this.f95393m.getValue()).floatValue();
            float fFloatValue2 = ((Number) this.f95393m.getValue()).floatValue() + fS;
            nk.q qVarA = nk.q.f134234e.a();
            qVarA.g(fU, fFloatValue, fY, fFloatValue2);
            qVarA.i(fU, fFloatValue, fY, fFloatValue2);
            qVarA.j(aISRLItemCopy$default);
            bVarC.e(qVarA);
            i11 = i12;
        }
        for (Object obj2 : listW2) {
            int i13 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            AISRLItem aISRLItemCopy$default2 = AISRLItem.copy$default((AISRLItem) obj2, 0.0d, 0.0d, AISRLItem.SIDE_SUPPORT, i13, 3, null);
            float fU2 = c2702d.u();
            float fY2 = c2702d.y();
            float fS2 = abstractC2759w0.S(aISRLItemCopy$default2.getPrice());
            canvas.drawLine(fU2, fS2, fY2, fS2, this.f95395o);
            float fFloatValue3 = fS2 - ((Number) this.f95393m.getValue()).floatValue();
            float fFloatValue4 = ((Number) this.f95393m.getValue()).floatValue() + fS2;
            nk.q qVarA2 = nk.q.f134234e.a();
            qVarA2.g(fU2, fFloatValue3, fY2, fFloatValue4);
            qVarA2.i(fU2, fFloatValue3, fY2, fFloatValue4);
            qVarA2.j(aISRLItemCopy$default2);
            bVarC.e(qVarA2);
            i10 = i13;
        }
        bVarC.b();
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        AISRLData aISRLDataT;
        Object objD = this.f95392l.d(i10, i11);
        String amountUnit = null;
        AISRLItem aISRLItem = objD instanceof AISRLItem ? (AISRLItem) objD : null;
        if (aISRLItem == null) {
            return false;
        }
        C7482p c7482p = this.f95398r;
        if (c7482p != null && (aISRLDataT = c7482p.t()) != null) {
            amountUnit = aISRLDataT.getAmountUnit();
        }
        if (amountUnit == null) {
            amountUnit = "";
        }
        AISRLInfo aISRLInfo = new AISRLInfo(0.0d, 0.0d, null, null, 0, 0, 0, 127, null);
        aISRLInfo.initInfo(aISRLItem, i10, i11, amountUnit);
        C2738p.f19487a.a(aISRLInfo);
        return true;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f95394n.setColor(aVar.d(".main_red.color"));
        this.f95395o.setColor(aVar.d(".main_green.color"));
        C2741q c2741qB = i().b();
        this.f95396p = c2741qB.e(b());
        c2741qB.m(c());
        this.f95397q = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        C7482p c7482p = abstractC2755vQ instanceof C7482p ? (C7482p) abstractC2755vQ : null;
        if (c7482p == null) {
            return;
        }
        this.f95398r = c7482p;
    }
}
