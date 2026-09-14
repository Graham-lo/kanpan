package fk;

import Rj.AbstractC2693a;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import Rj.y1;
import Sf.AbstractC2803q;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import gk.X0;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.apache.tika.utils.StringUtils;
import p254m.aicoin.kline.main.MainKlineFragment;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class e0 extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public Paint f95369A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public Paint f95370B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public int f95371C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public AbstractC2759w0 f95372D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public y1 f95373E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public X0 f95374F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public Double f95375G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public Double f95376H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public Double f95377I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public Double f95378J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public final ArrayList f95379K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public Paint f95380L;

    public e0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95371C = KLineManager.f142490O.a().j();
        this.f95379K = new ArrayList();
    }

    public static final List H(e0 e0Var, int i10) {
        return i10 < e0Var.f95379K.size() ? (List) e0Var.f95379K.get(i10) : AbstractC2803q.e(new AbstractC2693a.b("", e0Var.f95369A, true, false, null, false, 56, null));
    }

    /* JADX WARN: Code duplicated, block: B:52:0x0129  */
    /* JADX WARN: Code duplicated, block: B:59:0x018e  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        Rj.G gH;
        y1 y1Var;
        List<Map> listD;
        String str;
        String str2;
        C2702d c2702dD = j().d();
        if (c2702dD == null || (gH = j().h()) == null || (y1Var = this.f95373E) == null) {
            return;
        }
        if ((gH.B() || y1Var.E()) && KLineManager.f142490O.a().d0()) {
            this.f95379K.clear();
            float fG = y1Var.G();
            AbstractC2759w0 abstractC2759w0 = this.f95372D;
            double dR = abstractC2759w0 != null ? abstractC2759w0.R(fG) : 0.0d;
            X0 x10 = this.f95374F;
            if (x10 != null && (listD = x10.D()) != null) {
                for (Map map : listD) {
                    Double dValueOf = (Double) map.get("from");
                    if (dValueOf == null) {
                        dValueOf = Double.valueOf(0.0d);
                    }
                    this.f95375G = dValueOf;
                    Double dValueOf2 = (Double) map.get("to");
                    if (dValueOf2 == null) {
                        dValueOf2 = Double.valueOf(0.0d);
                    }
                    this.f95376H = dValueOf2;
                    double dDoubleValue = this.f95375G.doubleValue();
                    if (dR <= this.f95376H.doubleValue() && dDoubleValue <= dR) {
                        Double dValueOf3 = (Double) map.get(MainKlineFragment.KEY_AISRL_BIDS);
                        if (dValueOf3 == null) {
                            dValueOf3 = Double.valueOf(0.0d);
                        }
                        this.f95377I = dValueOf3;
                        Double dValueOf4 = (Double) map.get(MainKlineFragment.KEY_AISRL_ASKS);
                        if (dValueOf4 == null) {
                            dValueOf4 = Double.valueOf(0.0d);
                        }
                        this.f95378J = dValueOf4;
                        ArrayList arrayList = new ArrayList();
                        arrayList.add(new AbstractC2693a.b(i().c().getResources().getString(R.string.kline_vpvr_name) + ' ' + i().c().getResources().getString(R.string.kline_vpvr_buy), this.f95380L, true, false, null, false, 56, null));
                        Double d10 = this.f95377I;
                        if (d10 != null) {
                            double dDoubleValue2 = d10.doubleValue();
                            String strF = nk.h.f(nk.h.f134211a, dDoubleValue2, nk.A.b(dDoubleValue2, this.f95371C), 0, 4, null);
                            if (strF == null) {
                                str = "";
                            } else {
                                str = strF;
                            }
                        } else {
                            str = "";
                        }
                        arrayList.add(new AbstractC2693a.b(str, this.f95369A, true, false, null, false, 56, null));
                        arrayList.add(new AbstractC2693a.b(StringUtils.SPACE + i().c().getResources().getString(R.string.kline_vpvr_sell), this.f95380L, true, false, null, false, 56, null));
                        Double d11 = this.f95378J;
                        if (d11 != null) {
                            double dDoubleValue3 = d11.doubleValue();
                            String strF2 = nk.h.f(nk.h.f134211a, dDoubleValue3, nk.A.b(dDoubleValue3, this.f95371C), 0, 4, null);
                            if (strF2 == null) {
                                str2 = "";
                            } else {
                                str2 = strF2;
                            }
                        } else {
                            str2 = "";
                        }
                        arrayList.add(new AbstractC2693a.b(str2, this.f95370B, true, false, null, false, 56, null));
                        double dDoubleValue4 = this.f95378J.doubleValue() + this.f95377I.doubleValue();
                        arrayList.add(new AbstractC2693a.b(StringUtils.SPACE + i().c().getResources().getString(R.string.kline_vpvr_all) + nk.h.f(nk.h.f134211a, dDoubleValue4, nk.A.b(dDoubleValue4, this.f95371C), 0, 4, null), this.f95380L, true, false, null, false, 56, null));
                        this.f95379K.add(arrayList);
                    }
                }
            }
            y(canvas, c2702dD, this.f95379K.size(), new d0(this));
        }
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        E();
        C2741q c2741qB = i().b();
        c2741qB.e(b());
        this.f95372D = c2741qB.l(b());
        this.f95373E = c2741qB.m(c());
        AbstractC2755v abstractC2755vQ = q();
        X0 x10 = abstractC2755vQ instanceof X0 ? (X0) abstractC2755vQ : null;
        if (x10 == null) {
            return;
        }
        this.f95374F = x10;
        Paint paint = new Paint(1);
        paint.setColor(Color.parseColor("#FF1478FA"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        this.f95369A = paint;
        Paint paint2 = new Paint(1);
        paint2.setColor(Color.parseColor("#FFFF6901"));
        paint2.setTextSize(Xj.a.d(9));
        paint2.setAntiAlias(true);
        this.f95370B = paint2;
        Paint paint3 = new Paint(1);
        paint3.setColor(aVar.d(".price_info.unit_value"));
        paint3.setTextSize(Xj.a.d(9));
        paint3.setAntiAlias(true);
        this.f95380L = paint3;
    }
}
