package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;

/* JADX INFO: loaded from: classes7.dex */
public final class a0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final ak.h f95324l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final int f95325m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final double[] f95326n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint[] f95327o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Path f95328p;

    public a0(double[] dArr, C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95328p = new Path();
        this.f95324l = new ak.h(c2732n.b(), this, null, 4, null);
        int length = dArr.length;
        this.f95325m = length;
        this.f95326n = dArr;
        Paint[] paintArr = new Paint[length];
        for (int i10 = 0; i10 < length; i10++) {
            Paint paint = new Paint();
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(2.0f);
            paint.setPathEffect(new DashPathEffect(new float[]{Xj.a.b(3), Xj.a.b(2)}, 0.0f));
            paintArr[i10] = paint;
        }
        this.f95327o = paintArr;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        AbstractC2759w0 abstractC2759w0J = j().j();
        if (abstractC2759w0J == null || (c2702dD = j().d()) == null) {
            return;
        }
        int i10 = this.f95325m;
        for (int i11 = 0; i11 < i10; i11++) {
            float fS = abstractC2759w0J.S(this.f95326n[i11]);
            Path path = this.f95328p;
            path.reset();
            path.moveTo(c2702dD.u(), fS);
            path.lineTo(c2702dD.y(), fS);
            if (abstractC2759w0J.u() > this.f95326n[i11] && abstractC2759w0J.v() < this.f95326n[i11]) {
                canvas.drawPath(this.f95328p, this.f95327o[i11]);
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public ak.h j() {
        return this.f95324l;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        Paint[] paintArr = this.f95327o;
        int length = paintArr.length;
        int i10 = 0;
        int i11 = 0;
        while (i10 < length) {
            paintArr[i10].setColor(aVar.d("value_indicator_line_color_" + i11));
            i10++;
            i11++;
        }
    }
}
