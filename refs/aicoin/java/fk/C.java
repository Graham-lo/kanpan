package fk;

import Rj.AbstractC2693a;
import Rj.AbstractC2735o;
import Rj.AbstractC2755v;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2760w1;
import Rj.y1;
import Sf.AbstractC2801o;
import android.content.res.Resources;
import android.graphics.Canvas;
import android.graphics.Paint;
import gk.AbstractC7467h0;
import java.text.NumberFormat;
import java.util.ArrayList;
import java.util.Arrays;
import org.apache.tika.utils.StringUtils;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class C extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final ak.h f95015A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public int f95016B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public boolean f95017C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final ArrayList f95018D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public AbstractC7467h0 f95019E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public sp.aicoin_kline.core.indicator.config.F f95020F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public String f95021G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public String f95022H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public int f95023I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public int f95024J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public int f95025K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public int f95026L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public int f95027M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public Paint[] f95028N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public Paint f95029O;

    public C(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95016B = KLineManager.f142490O.a().j();
        this.f95018D = new ArrayList();
        this.f95021G = "";
        this.f95022H = "";
        this.f95028N = new Paint[0];
        this.f95029O = new Paint();
        this.f95015A = new ak.h(c2732n.b(), this, null, 4, null);
    }

    public C(C2732n c2732n, String str, String str2) {
        super(c2732n, str);
        this.f95016B = KLineManager.f142490O.a().j();
        this.f95018D = new ArrayList();
        this.f95021G = "";
        this.f95022H = "";
        this.f95028N = new Paint[0];
        this.f95029O = new Paint();
        this.f95015A = new ak.h(c2732n.b(), this, str2);
    }

    public final void H(int i10) {
        this.f95016B = i10;
    }

    public final void I(boolean z10) {
        this.f95017C = z10;
    }

    /* JADX WARN: Code duplicated, block: B:86:0x0223  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        Rj.G gH;
        C2702d c2702dD;
        AbstractC7467h0 abstractC7467h0;
        sp.aicoin_kline.core.indicator.config.F f10;
        y1 y1Var;
        Paint paintX;
        int i10;
        String strA;
        String string;
        y1 y1VarK = j().k();
        if (y1VarK == null || (gH = j().h()) == null || (c2702dD = j().d()) == null || (abstractC7467h0 = this.f95019E) == null || (f10 = this.f95020F) == null) {
            return;
        }
        boolean zJ = C2760w1.f19594a.j();
        ek.I[] iArrR = f10.r();
        this.f95018D.clear();
        if (this.f95021G.length() > 0) {
            this.f95018D.add(new AbstractC2693a.b(this.f95021G, A(), false, true, f10.n(), false, 36, null));
        }
        int iIntValue = ((Number) p162hb.e.c(nk.n.f(13), Integer.valueOf(gH.t()), Integer.valueOf(y1VarK.D()))).intValue();
        long jH = abstractC7467h0.u() ? y1VarK.H(iIntValue) : 0L;
        Long[] lArrY = abstractC7467h0.y();
        int iW = abstractC7467h0.w();
        int i11 = 0;
        boolean z10 = true;
        while (i11 < iW) {
            double[] dArr = abstractC7467h0.v()[i11];
            if (dArr.length == 0) {
                y1Var = y1VarK;
            } else {
                int length = dArr.length;
                y1Var = y1VarK;
                int i12 = 0;
                while (true) {
                    if (i12 < length) {
                        if (!Double.isNaN(dArr[i12])) {
                            if (abstractC7467h0.u()) {
                                iIntValue = AbstractC2801o.w0(lArrY, Long.valueOf(jH));
                            }
                            if (!gH.B() && !y1Var.E()) {
                                iIntValue = nk.z.g(dArr) - 1;
                            }
                            double d10 = (iIntValue < 0 || iIntValue >= dArr.length) ? Double.NaN : dArr[iIntValue];
                            ek.I i13 = iArrR[i11];
                            Resources resources = i().c().getResources();
                            if (resources == null || Double.isNaN(d10)) {
                                f10 = f10;
                                zJ = zJ;
                                iArrR = iArrR;
                            } else {
                                String strN = f10.n();
                                String strA2 = i13.a();
                                if (f10.t()) {
                                    ek.w wVar = f10.l()[i11];
                                    if (wVar.e() > 0) {
                                        strA2 = strN + nk.h.d(nk.h.f134211a, wVar.b(), String.valueOf(wVar.b()), 0, 4, null);
                                    } else {
                                        strA2 = strN + nk.h.d(nk.h.f134211a, wVar.g(), String.valueOf(wVar.g()), 0, 4, null);
                                    }
                                }
                                String str = strA2 + ':';
                                if (D()) {
                                    paintX = this.f95028N[i11];
                                } else {
                                    paintX = f10.q() == 33 ? this.f95029O : x(i11);
                                }
                                nk.o oVar = nk.o.f134231a;
                                if (AbstractC7609s.f(strN, oVar.a("position"))) {
                                    KLineManager.a aVar = KLineManager.f142490O;
                                    String strM = aVar.a().M();
                                    int iHashCode = strM.hashCode();
                                    if (iHashCode != 0) {
                                        if (iHashCode != 3059345) {
                                            if (iHashCode == 3599278 && strM.equals("usdt")) {
                                                string = "%s USDT";
                                            } else {
                                                string = resources.getString(R.string.kline_indicator_position_lot);
                                            }
                                        } else if (strM.equals("coin")) {
                                            string = "%s " + aVar.a().h();
                                        } else {
                                            string = resources.getString(R.string.kline_indicator_position_lot);
                                        }
                                    } else if (strM.equals("")) {
                                        string = "";
                                    } else {
                                        string = resources.getString(R.string.kline_indicator_position_lot);
                                    }
                                    p167hg.T t10 = p167hg.T.f97914a;
                                    strA = String.format(string, Arrays.copyOf(new Object[]{nk.h.f(nk.h.f134211a, d10, NumberFormat.getNumberInstance().format(d10), 0, 4, null)}, 1));
                                } else if (AbstractC7609s.f(strN, oVar.a("fundflow"))) {
                                    paintX.setColor(d10 >= 0.0d ? this.f95023I : this.f95024J);
                                    String str2 = StringUtils.SPACE + resources.getString(R.string.kline_titles_fund_in_flow);
                                    String str3 = StringUtils.SPACE + resources.getString(R.string.kline_titles_fund_out_flow);
                                    if (d10 < 0.0d) {
                                        str2 = str3;
                                    }
                                    StringBuilder sb2 = new StringBuilder();
                                    sb2.append(str2);
                                    nk.h hVar = nk.h.f134211a;
                                    sb2.append(nk.h.f(hVar, Math.abs(d10), nk.h.i(hVar, Math.abs(d10), false, 0, null, 14, null), 0, 4, null));
                                    strA = sb2.toString();
                                } else if (AbstractC7609s.f(strN, oVar.a("ai-li")) || AbstractC7609s.f(strN, oVar.a("ai-bst"))) {
                                    double d11 = d10;
                                    if (i11 != 0) {
                                        i10 = i11 != 1 ? this.f95027M : this.f95026L;
                                    } else {
                                        i10 = this.f95025K;
                                    }
                                    paintX.setColor(i10);
                                    StringBuilder sb3 = new StringBuilder();
                                    sb3.append(str);
                                    strA = kk.h.a(sb3, nk.h.f(nk.h.f134211a, d11, nk.l.f134222a.m(d11, 0, 9, this.f95016B, AbstractC2735o.a(i())), 0, 4, null), ' ');
                                } else if (AbstractC7609s.f(strN, oVar.a("ai-netvol"))) {
                                    strA = str + nk.h.f(nk.h.f134211a, d10, NumberFormat.getNumberInstance().format(d10), 0, 4, null);
                                } else {
                                    double d12 = d10;
                                    if (AbstractC7609s.f(strN, oVar.a("fr")) || AbstractC7609s.f(strN, oVar.a("pfr"))) {
                                        StringBuilder sb4 = new StringBuilder();
                                        sb4.append(str);
                                        strA = kk.h.a(sb4, nk.l.n(nk.l.f134222a, d12 * ((double) 100), 0, 9, 4, null, 16, null), '%');
                                    } else {
                                        StringBuilder sb5 = new StringBuilder();
                                        sb5.append(str);
                                        strA = kk.h.a(sb5, nk.h.f(nk.h.f134211a, d12, nk.l.f134222a.m(d12, 0, 9, this.f95016B, AbstractC2735o.a(i())), 0, 4, null), ' ');
                                    }
                                }
                                this.f95018D.add(new AbstractC2693a.b(strA, paintX, false, false, f10.n(), false, 44, null));
                            }
                            z10 = false;
                            break;
                        }
                        i12++;
                    }
                }
                i11++;
                y1VarK = y1Var;
                gH = gH;
                abstractC7467h0 = abstractC7467h0;
                f10 = f10;
                zJ = zJ;
                iArrR = iArrR;
            }
            abstractC7467h0 = abstractC7467h0;
            f10 = f10;
            zJ = zJ;
            iArrR = iArrR;
            i11++;
            y1VarK = y1Var;
            gH = gH;
            abstractC7467h0 = abstractC7467h0;
            f10 = f10;
            zJ = zJ;
            iArrR = iArrR;
        }
        sp.aicoin_kline.core.indicator.config.F f11 = f10;
        boolean z11 = zJ;
        if (z10 && !f11.s() && Zj.h.f27612a.b().contains(Integer.valueOf(f11.q()))) {
            this.f95018D.clear();
            this.f95018D.add(new AbstractC2693a.b(this.f95022H, A(), false, true, f11.n(), false, 36, null));
        }
        if (z11 || !f11.s() || this.f95017C) {
            z(canvas, c2702dD, this.f95018D);
        }
    }

    @Override // Rj.AbstractC2744r0
    public ak.h j() {
        return this.f95015A;
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        AbstractC2755v abstractC2755vQ = q();
        AbstractC7467h0 abstractC7467h0 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
        if (abstractC7467h0 == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fX = abstractC7467h0.x();
        this.f95019E = abstractC7467h0;
        this.f95020F = fX;
        Paint paint = new Paint(A());
        KLineManager.a aVar2 = KLineManager.f142490O;
        paint.setColor(aVar.d(aVar2.a().V() ? ".main_red.color" : ".main_green.color"));
        Qf.H h10 = Qf.H.f17640a;
        Paint paint2 = new Paint(A());
        paint2.setColor(aVar.d(aVar2.a().V() ? ".main_green.color" : ".main_red.color"));
        this.f95028N = new Paint[]{paint, paint2};
        Paint paint3 = new Paint(A());
        paint3.setColor(nk.b.b((String) p162hb.e.c(aVar.w(), "#B57C26", "#E69D30")));
        this.f95029O = paint3;
        this.f95023I = aVar.u(10);
        this.f95024J = aVar.u(11);
        this.f95025K = aVar.r();
        this.f95026L = aVar.m();
        this.f95027M = fX.k()[0].a();
        Resources resources = i().c().getResources();
        if (resources == null) {
            return;
        }
        String strN = fX.n();
        nk.o oVar = nk.o.f134231a;
        if (AbstractC7609s.f(strN, oVar.a("fundflow"))) {
            strN = resources.getString(R.string.kline_titles_fund_flow);
        } else if (AbstractC7609s.f(strN, oVar.a("position"))) {
            strN = resources.getString(R.string.kline_titles_position);
        } else if (AbstractC7609s.f(strN, oVar.a("ai-fdi"))) {
            strN = resources.getString(R.string.kline_titles_ai_fdi);
        } else if (AbstractC7609s.f(strN, oVar.a("ai-pd"))) {
            strN = resources.getString(R.string.kline_titles_ai_pd);
        } else if (AbstractC7609s.f(strN, oVar.a("ai-li"))) {
            strN = resources.getString(R.string.kline_titles_ai_li);
        } else if (AbstractC7609s.f(strN, oVar.a("ai-bsi"))) {
            strN = resources.getString(R.string.kline_titles_ai_bsi);
        } else if (AbstractC7609s.f(strN, oVar.a("ai-netvol"))) {
            strN = resources.getString(R.string.kline_titles_ai_net_vol);
        } else if (AbstractC7609s.f(strN, oVar.a("ai-bst"))) {
            strN = resources.getString(R.string.kline_titles_ai_bst);
        }
        if (fX.t() || strN.length() == 0) {
            this.f95021G = kk.i.a(strN, ": ");
            return;
        }
        StringBuffer stringBuffer = new StringBuffer();
        if (fX.l().length == 0) {
            stringBuffer.append(strN);
            stringBuffer.append(StringUtils.SPACE);
        } else {
            stringBuffer.append(strN);
            stringBuffer.append("(");
            boolean z10 = false;
            for (ek.w wVar : fX.l()) {
                if (wVar.f()) {
                    if (z10) {
                        stringBuffer.append(",");
                    }
                    if (wVar.e() > 0) {
                        stringBuffer.append(nk.h.d(nk.h.f134211a, wVar.b(), String.valueOf(wVar.b()), 0, 4, null));
                    } else {
                        stringBuffer.append(nk.h.d(nk.h.f134211a, wVar.g(), String.valueOf(wVar.g()), 0, 4, null));
                    }
                    z10 = true;
                }
            }
            stringBuffer.append("): ");
        }
        this.f95021G = stringBuffer.toString();
        this.f95022H = resources.getString(R.string.kline_titles_not_support, strN);
    }
}
