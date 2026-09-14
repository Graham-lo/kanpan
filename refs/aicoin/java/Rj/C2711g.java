package Rj;

import android.content.res.Resources;
import android.graphics.Canvas;
import android.graphics.Paint;
import com.tencent.android.tpns.mqtt.MqttTopic;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import kotlin.jvm.internal.DefaultConstructorMarker;
import org.apache.tika.utils.StringUtils;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.data.DataItemClickInfo;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.g, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2711g extends AbstractC2693a {

    /* JADX INFO: renamed from: T, reason: collision with root package name */
    public static final a f19385T = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final DecimalFormat f19386A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final SimpleDateFormat f19387B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final int f19388C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final Paint f19389D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public final Paint f19390E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public final List f19391F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public String f19392G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public String f19393H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public String f19394I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public String f19395J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public String f19396K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public String f19397L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public String f19398M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public int f19399N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public int f19400O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public int f19401P;

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public double f19402Q;

    /* JADX INFO: renamed from: R, reason: collision with root package name */
    public double f19403R;

    /* JADX INFO: renamed from: S, reason: collision with root package name */
    public KLineManager f19404S;

    /* JADX INFO: renamed from: Rj.g$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C2711g(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19386A = new DecimalFormat("0.00");
        this.f19387B = new SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault());
        this.f19388C = Xj.a.d(0);
        Paint paint = new Paint();
        this.f19389D = paint;
        Paint paint2 = new Paint();
        this.f19390E = paint2;
        this.f19391F = Sf.r.q(new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 56, null), new AbstractC2693a.b("", paint2, false, false, null, false, 56, null), new AbstractC2693a.b("", paint, false, false, null, false, 56, null), new AbstractC2693a.b("", paint, false, false, null, false, 56, null));
        this.f19392G = "";
        this.f19393H = "";
        this.f19394I = "";
        this.f19395J = "";
        this.f19396K = "";
        this.f19397L = "";
        this.f19398M = "";
    }

    @Override // Rj.AbstractC2693a
    public int C() {
        return this.f19388C;
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        G gH;
        C2702d c2702dD;
        C2765z c2765zH;
        int i10;
        if (m() == 1) {
            KLineManager.a aVar = KLineManager.f142490O;
            if (aVar.a().f() != -1) {
                aVar.a().k0(-1);
                C2738p.f19487a.e(null);
                return;
            }
            return;
        }
        y1 y1VarK = j().k();
        if (y1VarK == null || (gH = j().h()) == null || (c2702dD = j().d()) == null || (c2765zH = j().i().h(c())) == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        int iIntValue = ((Number) p162hb.e.c(nk.n.f(13), Integer.valueOf(gH.t()), Integer.valueOf(y1VarK.D()))).intValue();
        if (nk.z.a(c2765zH.C(), iIntValue)) {
            Sj.b bVar = (Sj.b) c2765zH.C().get(iIntValue);
            Sj.b bVarD = iIntValue == iD ? nk.c.f134195a.d(bVar) : bVar;
            long jE = bVarD.e();
            double d10 = bVarD.d();
            double dB = bVarD.b();
            double dC = bVarD.c();
            double dA = bVarD.a();
            double dF = bVarD.f();
            AbstractC2693a.b bVar2 = (AbstractC2693a.b) this.f19391F.get(0);
            StringBuilder sb2 = new StringBuilder();
            Sj.b bVar3 = bVarD;
            sb2.append(this.f19387B.format(new Date(jE)));
            sb2.append(' ');
            bVar2.g(sb2.toString());
            AbstractC2693a.b bVar4 = (AbstractC2693a.b) this.f19391F.get(1);
            StringBuilder sb3 = new StringBuilder();
            sb3.append(this.f19392G);
            nk.l lVar = nk.l.f134222a;
            sb3.append(lVar.j(d10, AbstractC2735o.a(i())));
            sb3.append(' ');
            bVar4.g(sb3.toString());
            ((AbstractC2693a.b) this.f19391F.get(1)).h(!Double.isNaN(d10));
            ((AbstractC2693a.b) this.f19391F.get(2)).g(this.f19393H + lVar.j(dB, AbstractC2735o.a(i())) + ' ');
            ((AbstractC2693a.b) this.f19391F.get(2)).h(Double.isNaN(dB) ^ true);
            ((AbstractC2693a.b) this.f19391F.get(3)).g(this.f19394I + lVar.j(dC, AbstractC2735o.a(i())) + ' ');
            ((AbstractC2693a.b) this.f19391F.get(3)).h(Double.isNaN(dC) ^ true);
            ((AbstractC2693a.b) this.f19391F.get(4)).g(this.f19395J + lVar.j(dA, AbstractC2735o.a(i())) + ' ');
            ((AbstractC2693a.b) this.f19391F.get(4)).h(Double.isNaN(dA) ^ true);
            int i11 = iIntValue + (-1);
            double dA2 = nk.z.a(c2765zH.C(), i11) ? ((Sj.b) c2765zH.C().get(i11)).a() : bVar.a();
            double d11 = 100;
            double dA3 = ((bVar.a() - dA2) * d11) / dA2;
            this.f19403R = dA3;
            String strL = nk.l.l(lVar, bVar.a() - dA2, null, 2, null);
            StringBuilder sb4 = new StringBuilder();
            sb4.append(this.f19386A.format(dA3));
            sb4.append("%(");
            String strA = kk.h.a(sb4, strL, ')');
            if (dA3 > 0.0d) {
                strA = MqttTopic.SINGLE_LEVEL_WILDCARD + strA;
            }
            ((AbstractC2693a.b) this.f19391F.get(5)).h(!Double.isNaN(dA3));
            ((AbstractC2693a.b) this.f19391F.get(5)).g(this.f19396K);
            ((AbstractC2693a.b) this.f19391F.get(6)).h(!Double.isNaN(dA3));
            Paint paintC = ((AbstractC2693a.b) this.f19391F.get(6)).c();
            if (dA3 == 0.0d) {
                i10 = this.f19399N;
            } else if (KLineManager.f142490O.a().V()) {
                i10 = dA3 > 0.0d ? this.f19401P : this.f19400O;
            } else {
                i10 = dA3 > 0.0d ? this.f19400O : this.f19401P;
            }
            paintC.setColor(i10);
            ((AbstractC2693a.b) this.f19391F.get(6)).g(strA + ' ');
            double dB2 = ((bVar.b() - bVar.c()) * d11) / dA2;
            this.f19402Q = dB2;
            String str = this.f19386A.format(dB2) + '%';
            ((AbstractC2693a.b) this.f19391F.get(7)).h(!Double.isNaN(dB2));
            ((AbstractC2693a.b) this.f19391F.get(7)).g(this.f19397L + str);
            Sj.b bVarM = c2765zH.M();
            double dA4 = ((bVarM != null ? bVarM.a() : 0.0d) / bVar3.d()) - ((double) 1);
            String str2 = this.f19386A.format(dA4 * d11) + '%';
            KLineManager.a aVar2 = KLineManager.f142490O;
            if (aVar2.a().Y()) {
                ((AbstractC2693a.b) this.f19391F.get(8)).h(!Double.isNaN(dA4));
                ((AbstractC2693a.b) this.f19391F.get(8)).g(StringUtils.SPACE + this.f19398M + ": " + str2 + ' ');
            }
            if (aVar2.a().f() != iIntValue) {
                DataItemClickInfo dataItemClickInfo = new DataItemClickInfo(jE, lVar.j(d10, AbstractC2735o.a(i())), lVar.j(dB, AbstractC2735o.a(i())), lVar.j(dC, AbstractC2735o.a(i())), lVar.j(dA, AbstractC2735o.a(i())), strL, String.valueOf(this.f19403R), String.valueOf(this.f19402Q), String.valueOf(dF), iIntValue, str2);
                aVar2.a().k0(iIntValue);
                C2738p.f19487a.e(dataItemClickInfo);
            }
        }
        KLineManager kLineManager = this.f19404S;
        if (AbstractC7609s.f(kLineManager != null ? kLineManager.C() : null, "on_kline")) {
            z(canvas, c2702dD, this.f19391F);
        }
    }

    @Override // Rj.AbstractC2744r0
    public int m() {
        G gH;
        y1 y1VarK = j().k();
        if (y1VarK == null || (gH = j().h()) == null) {
            return 1;
        }
        return (y1VarK.E() || gH.B()) ? 0 : 1;
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        Paint paint = this.f19389D;
        paint.setColor(aVar.d(".price_info.unit_value"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        this.f19390E.set(this.f19389D);
        Resources resources = i().c().getResources();
        this.f19392G = resources.getString(R.string.kline_titles_open);
        this.f19393H = resources.getString(R.string.kline_titles_high);
        this.f19394I = resources.getString(R.string.kline_titles_low);
        this.f19395J = resources.getString(R.string.kline_titles_close);
        this.f19396K = resources.getString(R.string.kline_titles_growth_rate);
        this.f19397L = resources.getString(R.string.kline_titles_amplitude);
        this.f19398M = resources.getString(R.string.kline_info_window_diff_rate1);
        ((AbstractC2693a.b) this.f19391F.get(5)).h(true);
        ((AbstractC2693a.b) this.f19391F.get(6)).h(true);
        ((AbstractC2693a.b) this.f19391F.get(7)).h(true);
        ((AbstractC2693a.b) this.f19391F.get(8)).h(false);
        this.f19399N = aVar.d(".price_info.unit_value");
        this.f19400O = aVar.d(".growth_info.positive");
        this.f19401P = aVar.d(".growth_info.negative");
        this.f19404S = KLineManager.f142490O.a();
    }
}
