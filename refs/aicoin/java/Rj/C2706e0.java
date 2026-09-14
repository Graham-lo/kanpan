package Rj;

import android.content.res.Resources;
import android.graphics.Canvas;
import android.graphics.Paint;
import com.tencent.android.tpns.mqtt.MqttTopic;
import java.text.DecimalFormat;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.data.DataItemClickInfo;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.e0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2706e0 extends AbstractC2693a {

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public static final a f19364Q = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final DecimalFormat f19365A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final int f19366B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Paint f19367C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final Paint f19368D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public final List f19369E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public String f19370F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public String f19371G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public String f19372H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public String f19373I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public String f19374J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public String f19375K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public int f19376L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public int f19377M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public int f19378N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public double f19379O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public double f19380P;

    /* JADX INFO: renamed from: Rj.e0$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C2706e0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19365A = new DecimalFormat("0.00");
        this.f19366B = Xj.a.d(0);
        Paint paint = new Paint();
        this.f19367C = paint;
        Paint paint2 = new Paint();
        this.f19368D = paint2;
        this.f19369E = Sf.r.q(new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 56, null), new AbstractC2693a.b("", paint2, false, false, null, false, 56, null), new AbstractC2693a.b("", paint, false, false, null, false, 56, null));
        this.f19370F = "";
        this.f19371G = "";
        this.f19372H = "";
        this.f19373I = "";
        this.f19374J = "";
        this.f19375K = "";
    }

    @Override // Rj.AbstractC2693a
    public int C() {
        return this.f19366B;
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarK;
        C2702d c2702dD;
        C2765z c2765zH;
        int i10;
        if (m() == 1 || (y1VarK = j().k()) == null || (c2702dD = j().d()) == null || (c2765zH = j().i().h(c())) == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        int iD2 = y1VarK.D();
        if (nk.z.a(c2765zH.C(), iD2)) {
            Sj.b bVar = (Sj.b) c2765zH.C().get(iD2);
            Sj.b bVarD = iD2 == iD ? nk.c.f134195a.d(bVar) : bVar;
            double d10 = bVarD.d();
            double dB = bVarD.b();
            double dC = bVarD.c();
            double dA = bVarD.a();
            long jE = bVarD.e();
            double dF = bVarD.f();
            AbstractC2693a.b bVar2 = (AbstractC2693a.b) this.f19369E.get(0);
            StringBuilder sb2 = new StringBuilder();
            sb2.append(this.f19370F);
            nk.l lVar = nk.l.f134222a;
            sb2.append(lVar.j(d10, AbstractC2735o.a(i())));
            sb2.append(' ');
            bVar2.g(sb2.toString());
            ((AbstractC2693a.b) this.f19369E.get(0)).h(!Double.isNaN(d10));
            AbstractC2693a.b bVar3 = (AbstractC2693a.b) this.f19369E.get(1);
            StringBuilder sb3 = new StringBuilder();
            sb3.append(this.f19371G);
            Sj.b bVar4 = bVarD;
            sb3.append(lVar.j(bVar4.b(), AbstractC2735o.a(i())));
            sb3.append(' ');
            bVar3.g(sb3.toString());
            ((AbstractC2693a.b) this.f19369E.get(1)).h(!Double.isNaN(dB));
            ((AbstractC2693a.b) this.f19369E.get(2)).g(this.f19372H + lVar.j(bVar4.c(), AbstractC2735o.a(i())) + ' ');
            ((AbstractC2693a.b) this.f19369E.get(2)).h(Double.isNaN(dC) ^ true);
            ((AbstractC2693a.b) this.f19369E.get(3)).g(this.f19373I + lVar.j(bVar4.a(), AbstractC2735o.a(i())) + ' ');
            ((AbstractC2693a.b) this.f19369E.get(3)).h(Double.isNaN(dA) ^ true);
            int i11 = iD2 + (-1);
            double dA2 = nk.z.a(c2765zH.C(), i11) ? ((Sj.b) c2765zH.C().get(i11)).a() : bVar.a();
            double d11 = 100;
            double dA3 = ((bVar.a() - dA2) * d11) / dA2;
            this.f19380P = dA3;
            String strL = nk.l.l(lVar, bVar.a() - dA2, null, 2, null);
            double d12 = dA2;
            StringBuilder sb4 = new StringBuilder();
            sb4.append(this.f19365A.format(dA3));
            sb4.append("%(");
            String strA = kk.h.a(sb4, strL, ')');
            if (dA3 > 0.0d) {
                strA = MqttTopic.SINGLE_LEVEL_WILDCARD + strA;
            }
            ((AbstractC2693a.b) this.f19369E.get(4)).h(!Double.isNaN(dA3));
            ((AbstractC2693a.b) this.f19369E.get(4)).g(this.f19374J);
            ((AbstractC2693a.b) this.f19369E.get(5)).h(!Double.isNaN(dA3));
            Paint paintC = ((AbstractC2693a.b) this.f19369E.get(5)).c();
            if (dA3 == 0.0d) {
                i10 = this.f19376L;
            } else if (KLineManager.f142490O.a().V()) {
                i10 = dA3 > 0.0d ? this.f19378N : this.f19377M;
            } else {
                i10 = dA3 > 0.0d ? this.f19377M : this.f19378N;
            }
            paintC.setColor(i10);
            ((AbstractC2693a.b) this.f19369E.get(5)).g(strA + ' ');
            double dB2 = ((bVar.b() - bVar.c()) * d11) / d12;
            this.f19379O = dB2;
            String str = this.f19365A.format(dB2) + '%';
            ((AbstractC2693a.b) this.f19369E.get(6)).h(!Double.isNaN(dB2));
            ((AbstractC2693a.b) this.f19369E.get(6)).g(this.f19375K + str);
            C2738p.f19487a.e(new DataItemClickInfo(jE, lVar.j(d10, AbstractC2735o.a(i())), lVar.j(dB, AbstractC2735o.a(i())), lVar.j(dC, AbstractC2735o.a(i())), lVar.j(dA, AbstractC2735o.a(i())), strL, String.valueOf(this.f19380P), String.valueOf(this.f19379O), String.valueOf(dF), 0, null, 1536, null));
        }
        if (AbstractC7609s.f(KLineManager.f142490O.a().C(), "on_kline")) {
            z(canvas, c2702dD, this.f19369E);
        }
    }

    @Override // Rj.AbstractC2744r0
    public int m() {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return 1;
        }
        return !y1VarK.E() ? 1 : 0;
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        Paint paint = this.f19367C;
        paint.setColor(aVar.d(".price_info.unit_value"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        this.f19368D.set(this.f19367C);
        Resources resources = i().c().getResources();
        this.f19370F = resources.getString(R.string.kline_titles_open);
        this.f19371G = resources.getString(R.string.kline_titles_high);
        this.f19372H = resources.getString(R.string.kline_titles_low);
        this.f19373I = resources.getString(R.string.kline_titles_close);
        this.f19374J = resources.getString(R.string.kline_titles_growth_rate);
        this.f19375K = resources.getString(R.string.kline_titles_amplitude);
        ((AbstractC2693a.b) this.f19369E.get(4)).h(true);
        ((AbstractC2693a.b) this.f19369E.get(5)).h(true);
        ((AbstractC2693a.b) this.f19369E.get(6)).h(true);
        this.f19376L = aVar.d(".price_info.unit_value");
        this.f19377M = aVar.d(".growth_info.positive");
        this.f19378N = aVar.d(".growth_info.negative");
    }
}
