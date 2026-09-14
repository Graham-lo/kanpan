package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class H0 extends AbstractC2693a {

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public static final a f19134I = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final SimpleDateFormat f19135A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final int f19136B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Paint f19137C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final Paint f19138D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public final List f19139E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public int f19140F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public int f19141G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public int f19142H;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public H0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19135A = new SimpleDateFormat("MM-dd HH:mm", Locale.getDefault());
        this.f19136B = Xj.a.d(0);
        Paint paint = new Paint();
        this.f19137C = paint;
        Paint paint2 = new Paint();
        this.f19138D = paint2;
        this.f19139E = Sf.r.q(new AbstractC2693a.b("", paint, false, false, null, false, 60, null), new AbstractC2693a.b("", paint2, false, false, null, false, 60, null), new AbstractC2693a.b("", paint, false, false, null, false, 60, null));
    }

    public static final List H(List list, H0 h10, int i10) {
        String str;
        int i11;
        Sj.f fVar = (Sj.f) Sf.z.D0((List) list.get(i10));
        if (fVar == null) {
            return Sf.r.n();
        }
        if (fVar.c().length() > 0) {
            str = "(" + fVar.c() + ") ";
        } else {
            str = "";
        }
        ((AbstractC2693a.b) h10.f19139E.get(0)).g(fVar.b() + ' ' + str + fVar.d() + ' ');
        AbstractC2693a.b bVar = (AbstractC2693a.b) h10.f19139E.get(1);
        StringBuilder sb2 = new StringBuilder();
        sb2.append(fVar.h());
        sb2.append(' ');
        bVar.g(sb2.toString());
        Paint paintC = ((AbstractC2693a.b) h10.f19139E.get(1)).c();
        String strI = fVar.i();
        if (AbstractC7609s.f(strI, "")) {
            i11 = h10.f19140F;
        } else if (KLineManager.f142490O.a().V()) {
            i11 = AbstractC7609s.f(strI, "buy") ? h10.f19142H : h10.f19141G;
        } else {
            i11 = AbstractC7609s.f(strI, "buy") ? h10.f19141G : h10.f19142H;
        }
        paintC.setColor(i11);
        ((AbstractC2693a.b) h10.f19139E.get(2)).g(h10.f19135A.format(new Date(fVar.j() * 1000)));
        return h10.f19139E;
    }

    @Override // Rj.AbstractC2693a
    public int C() {
        return this.f19136B;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        C2765z c2765zH;
        if (m() == 1 || j().k() == null || j().h() == null || (c2702dD = j().d()) == null || (c2765zH = j().i().h(c())) == null) {
            return;
        }
        c2765zH.D();
        nk.n.f(13);
        List listU = c2765zH.U();
        y(canvas, c2702dD, listU.size(), new G0(listU, this));
    }

    @Override // Rj.AbstractC2744r0
    public int m() {
        G gH;
        if (j().k() == null || (gH = j().h()) == null) {
            return 1;
        }
        return gH.B() ? 1 : 0;
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        Paint paint = this.f19137C;
        paint.setColor(aVar.d(".price_info.unit_value"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        this.f19138D.set(this.f19137C);
        this.f19140F = aVar.d(".price_info.unit_value");
        this.f19141G = aVar.d(".growth_info.positive");
        this.f19142H = aVar.d(".growth_info.negative");
    }
}
