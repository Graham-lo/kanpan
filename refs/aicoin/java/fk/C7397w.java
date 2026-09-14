package fk;

import Rj.AbstractC2744r0;
import Rj.C2702d;
import Rj.C2732n;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import java.util.List;

/* JADX INFO: renamed from: fk.w, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7397w extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public C2702d f95575l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95576m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95577n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95578o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95579p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95580q;

    public C7397w(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint(1);
        paint.setColor(Color.parseColor("#F5F6F8"));
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        this.f95576m = paint;
        Paint paint2 = new Paint(1);
        paint2.setColor(Color.parseColor("#D8DDE5"));
        Paint.Style style2 = Paint.Style.STROKE;
        paint2.setStyle(style2);
        paint2.setStrokeWidth(v(1.0f));
        Paint paint3 = new Paint(1);
        paint3.setColor(Color.parseColor("#88000000"));
        paint3.setStyle(style);
        this.f95577n = paint3;
        Paint paint4 = new Paint(1);
        paint4.setColor(-1);
        paint4.setStyle(style);
        this.f95578o = paint4;
        Paint paint5 = new Paint(1);
        paint5.setColor(Color.parseColor("#222222"));
        paint5.setTextAlign(Paint.Align.CENTER);
        paint5.setTextSize(v(10.0f));
        this.f95579p = paint5;
        Paint paint6 = new Paint(1);
        paint6.setColor(Color.parseColor("#FF2D2D"));
        paint6.setStyle(style2);
        paint6.setStrokeWidth(v(2.0f));
        this.f95580q = paint6;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        Sj.e eVarB;
        Object obj;
        C2702d c2702d = this.f95575l;
        if (c2702d == null || (eVarB = C7399y.f95584C.b(c())) == null) {
            return;
        }
        float fV = v(1.0f);
        float fV2 = v(0.0f);
        float fV3 = v(24.0f);
        float fV4 = v(192.0f);
        float fV5 = v(72.0f);
        float f10 = fV4 + 0.0f + fV5;
        float f11 = 2;
        float f12 = fV2 * f11;
        float f13 = f11 * fV;
        float f14 = (3 * fV3) + f12 + f13;
        float fV6 = v(10.0f);
        float fU = c2702d.u();
        float fY = c2702d.y();
        float fZ = c2702d.z();
        float fP = c2702d.p();
        float fA = (eVarB.a() + fV6) + f10 <= fY ? eVarB.a() + fV6 : (eVarB.a() - fV6) - f10;
        float fB = eVarB.b() - (f14 / 2.0f);
        float fV7 = v(2.0f) + fU;
        float fV8 = (fY - f10) - v(2.0f);
        float fV9 = v(2.0f) + fZ;
        float fV10 = (fP - f14) - v(2.0f);
        float fO = p292ng.i.o(fA, Math.min(fV7, fV8), Math.max(fV7, fV8));
        float fO2 = p292ng.i.o(fB, Math.min(fV9, fV10), Math.max(fV9, fV10));
        canvas.drawRoundRect(new RectF(fO, fO2, f10 + fO, f14 + fO2), v(6.0f), v(6.0f), this.f95576m);
        float f15 = ((fV4 - f12) - f13) / 3.0f;
        int i10 = 0;
        while (true) {
            int i11 = 3;
            if (i10 >= 3) {
                return;
            }
            int i12 = 0;
            while (true) {
                obj = "--";
                if (i12 >= i11) {
                    break;
                }
                int i13 = (i10 * 3) + i12;
                float f16 = ((f15 + fV) * i12) + fO + fV2;
                float f17 = ((fV3 + fV) * i10) + fO2 + fV2;
                RectF rectF = new RectF(f16, f17, f16 + f15, f17 + fV3);
                Paint paint = this.f95578o;
                List listE = eVarB.e();
                paint.setColor(((Number) ((i13 < 0 || i13 >= listE.size()) ? Integer.valueOf(Color.parseColor("#E8ECEF")) : listE.get(i13))).intValue());
                canvas.drawRect(rectF, this.f95578o);
                if (i13 == 4) {
                    canvas.drawRect(rectF, this.f95580q);
                }
                List listD = eVarB.d();
                if (i13 >= 0 && i13 < listD.size()) {
                    obj = listD.get(i13);
                }
                String str = (String) obj;
                Paint paint2 = this.f95579p;
                int color = this.f95578o.getColor();
                paint2.setColor((((float) Color.blue(color)) * 0.114f) + ((((float) Color.green(color)) * 0.587f) + (((float) Color.red(color)) * 0.299f)) >= 140.0f ? -16777216 : -1);
                canvas.drawText(str, rectF.centerX(), rectF.centerY() - ((this.f95579p.ascent() + this.f95579p.descent()) / 2.0f), this.f95579p);
                i12++;
                i11 = 3;
            }
            float f18 = fO + fV4 + 0.0f;
            float f19 = ((fV3 + fV) * i10) + fO2 + fV2;
            RectF rectF2 = new RectF(f18, f19, (f18 + fV5) - fV2, f19 + fV3);
            canvas.drawRect(rectF2, this.f95577n);
            List listC = eVarB.c();
            if (i10 >= 0 && i10 < listC.size()) {
                obj = listC.get(i10);
            }
            String str2 = (String) obj;
            Paint paint3 = this.f95579p;
            int color2 = this.f95577n.getColor();
            paint3.setColor((((float) Color.blue(color2)) * 0.114f) + ((((float) Color.green(color2)) * 0.587f) + (((float) Color.red(color2)) * 0.299f)) >= 140.0f ? -16777216 : -1);
            canvas.drawText(str2, rectF2.centerX(), rectF2.centerY() - ((this.f95579p.ascent() + this.f95579p.descent()) / 2.0f), this.f95579p);
            i10++;
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        this.f95575l = i().b().e(b());
    }

    public final float v(float f10) {
        return f10 * i().c().getResources().getDisplayMetrics().density;
    }
}
