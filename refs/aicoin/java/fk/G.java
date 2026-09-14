package fk;

import Rj.AbstractC2735o;
import Rj.AbstractC2744r0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class G extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public float f95050A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public float f95051B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public mk.a f95052C;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final DecimalFormat f95053l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95054m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final RectF f95055n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final float f95056o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95057p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final float f95058q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final float f95059r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final float f95060s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final Rect f95061t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final SimpleDateFormat f95062u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public int f95063v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public int f95064w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public int f95065x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public float f95066y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public float f95067z;

    public G(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95053l = new DecimalFormat("0.00");
        this.f95054m = new Paint(1);
        this.f95055n = new RectF();
        this.f95056o = Xj.a.a(8.0f);
        this.f95057p = new Paint();
        this.f95058q = Xj.a.a(8.0f);
        this.f95059r = Xj.a.a(50.0f);
        this.f95060s = Xj.a.a(16.0f);
        this.f95061t = new Rect();
        this.f95062u = new SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault());
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2765z c2765zH;
        y1 y1VarK;
        Rj.G gH;
        C2702d c2702dD;
        int i10;
        boolean zF = nk.n.f(13);
        KLineManager.a aVar = KLineManager.f142490O;
        if (!AbstractC7609s.f(aVar.a().C(), "on_window") || zF || (c2765zH = j().i().h(c())) == null || (y1VarK = j().k()) == null || (gH = j().h()) == null || (c2702dD = j().d()) == null) {
            return;
        }
        if (gH.B() || y1VarK.E()) {
            int iD = c2765zH.D() - 1;
            int iD2 = y1VarK.D();
            Sj.b bVar = nk.z.a(c2765zH.C(), iD2) ? (Sj.b) c2765zH.C().get(iD2) : new Sj.b(0L, Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN);
            Sj.b bVarD = iD2 == iD ? nk.c.f134195a.d(bVar) : bVar;
            if (Double.isNaN(bVarD.d())) {
                return;
            }
            bVarD.d();
            int iAbs = Math.abs(y1VarK.q() - y1VarK.r());
            int iR = y1VarK.r() + (iAbs / 2);
            int i11 = aVar.a().Y() ? 9 : 8;
            if (iAbs < 40) {
                this.f95050A = c2702dD.y();
                this.f95066y = c2702dD.y() - Xj.a.a(122.0f);
            }
            if (iD2 < iR) {
                this.f95050A = c2702dD.y();
                this.f95066y = c2702dD.y() - Xj.a.a(122.0f);
            } else {
                this.f95066y = 0.0f;
                this.f95050A = Xj.a.a(122.0f);
            }
            this.f95067z = this.f95059r;
            this.f95051B = Xj.a.a(60.0f) + (this.f95060s * i11);
            String str = this.f95062u.format(new Date(bVarD.e()));
            nk.l lVar = nk.l.f134222a;
            String strJ = lVar.j(bVarD.d(), AbstractC2735o.a(i()));
            String strJ2 = lVar.j(bVarD.b(), AbstractC2735o.a(i()));
            String strJ3 = lVar.j(bVarD.c(), AbstractC2735o.a(i()));
            String strJ4 = lVar.j(bVarD.a(), AbstractC2735o.a(i()));
            int i12 = iD2 - 1;
            double dA = nk.z.a(c2765zH.C(), i12) ? ((Sj.b) c2765zH.C().get(i12)).a() : bVar.a();
            double d10 = 100;
            double dA2 = ((bVar.a() - dA) * d10) / dA;
            String str2 = this.f95053l.format(dA2) + '%';
            Paint paint = this.f95057p;
            Sj.b bVar2 = bVarD;
            mk.a aVar2 = this.f95052C;
            paint.setColor(aVar2 != null ? aVar2.i() : Color.parseColor("#FF59677B"));
            String strL = nk.l.l(lVar, bVar.a() - dA, null, 2, null);
            String str3 = this.f95053l.format(((bVar.b() - bVar.c()) * d10) / dA) + '%';
            Sj.b bVarM = c2765zH.M();
            String str4 = this.f95053l.format((((bVarM != null ? bVarM.a() : 0.0d) / bVar2.d()) - ((double) 1)) * d10) + '%';
            this.f95055n.set(this.f95066y, this.f95067z, this.f95050A, this.f95051B);
            RectF rectF = this.f95055n;
            float f10 = this.f95056o;
            canvas.drawRoundRect(rectF, f10, f10, this.f95054m);
            float f11 = this.f95060s + this.f95059r;
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_time) + ':', this.f95055n.left + this.f95058q, f11, this.f95057p);
            this.f95057p.getTextBounds(str, 0, str.length(), this.f95061t);
            canvas.drawText(str, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f11, this.f95057p);
            float f12 = f11 + this.f95060s;
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_open) + ':', this.f95055n.left + this.f95058q, f12, this.f95057p);
            this.f95057p.getTextBounds(strJ, 0, strJ.length(), this.f95061t);
            canvas.drawText(strJ, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f12, this.f95057p);
            float f13 = f12 + this.f95060s;
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_high) + ':', this.f95055n.left + this.f95058q, f13, this.f95057p);
            this.f95057p.getTextBounds(strJ2, 0, strJ2.length(), this.f95061t);
            canvas.drawText(strJ2, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f13, this.f95057p);
            float f14 = f13 + this.f95060s;
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_low) + ':', this.f95055n.left + this.f95058q, f14, this.f95057p);
            this.f95057p.getTextBounds(strJ3, 0, strJ3.length(), this.f95061t);
            canvas.drawText(strJ3, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f14, this.f95057p);
            float f15 = f14 + this.f95060s;
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_close) + ':', this.f95055n.left + this.f95058q, f15, this.f95057p);
            this.f95057p.getTextBounds(strJ4, 0, strJ4.length(), this.f95061t);
            canvas.drawText(strJ4, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f15, this.f95057p);
            float f16 = f15 + this.f95060s;
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_growth) + ':', this.f95055n.left + this.f95058q, f16, this.f95057p);
            this.f95057p.getTextBounds(strL, 0, strL.length(), this.f95061t);
            canvas.drawText(strL, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f16, this.f95057p);
            float f17 = f16 + this.f95060s;
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_growth_rate) + ':', this.f95055n.left + this.f95058q, f17, this.f95057p);
            this.f95057p.getTextBounds(str2, 0, str2.length(), this.f95061t);
            Paint paint2 = this.f95057p;
            if (dA2 == 0.0d) {
                i10 = this.f95063v;
            } else if (aVar.a().V()) {
                i10 = dA2 > 0.0d ? this.f95065x : this.f95064w;
            } else {
                i10 = dA2 > 0.0d ? this.f95064w : this.f95065x;
            }
            paint2.setColor(i10);
            canvas.drawText(str2, (this.f95055n.right - this.f95061t.width()) - this.f95058q, f17, this.f95057p);
            float f18 = f17 + this.f95060s;
            Paint paint3 = this.f95057p;
            mk.a aVar3 = this.f95052C;
            paint3.setColor(aVar3 != null ? aVar3.i() : Color.parseColor("#FF59677B"));
            canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_ampl) + ':', this.f95055n.left + this.f95058q, f18, this.f95057p);
            this.f95057p.getTextBounds(str3, 0, str3.length(), this.f95061t);
            canvas.drawText(str3, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f18, this.f95057p);
            float f19 = f18 + this.f95060s;
            if (aVar.a().Y()) {
                canvas.drawText(i().c().getResources().getString(R.string.kline_info_window_diff_rate) + ':', this.f95055n.left + this.f95058q, f19, this.f95057p);
                this.f95057p.getTextBounds(str4, 0, str4.length(), this.f95061t);
                canvas.drawText(str4, (this.f95055n.right - ((float) this.f95061t.width())) - this.f95058q, f19, this.f95057p);
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f95052C = aVar;
        Paint paint = this.f95054m;
        paint.setColor(aVar.j());
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint.setAntiAlias(true);
        Paint paint2 = this.f95057p;
        paint2.setTextSize(Xj.a.c(9.0f));
        paint2.setAntiAlias(true);
        paint2.setStyle(style);
        paint2.setColor(aVar.i());
        this.f95063v = aVar.d(".price_info.unit_value");
        this.f95064w = aVar.d(".growth_info.positive");
        this.f95065x = aVar.d(".growth_info.negative");
    }
}
