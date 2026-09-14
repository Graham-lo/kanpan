package fk;

import Rj.AbstractC2693a;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2765z;
import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.List;
import org.apache.tika.utils.StringUtils;

/* JADX INFO: loaded from: classes7.dex */
public final class g0 extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final Paint f95387A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final Paint f95388B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Paint f95389C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final Paint f95390D;

    public g0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95387A = new Paint();
        this.f95388B = new Paint();
        this.f95389C = new Paint();
        this.f95390D = new Paint();
    }

    public static final List H(List list, g0 g0Var, int i10) {
        Paint paint;
        Sj.k kVar = (Sj.k) list.get(i10);
        int iC = kVar.c();
        if (iC != 0) {
            paint = iC != 1 ? g0Var.f95390D : g0Var.f95389C;
        } else {
            paint = g0Var.f95388B;
        }
        Paint paint2 = paint;
        return Sf.r.q(new AbstractC2693a.b(kVar.a(), g0Var.f95387A, true, false, null, false, 56, null), new AbstractC2693a.b(StringUtils.SPACE + kVar.b(), paint2, true, false, null, false, 56, null), new AbstractC2693a.b(StringUtils.SPACE + kVar.d(), g0Var.f95387A, true, false, null, false, 56, null));
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        C2765z c2765zH = j().i().h(c());
        if (c2765zH == null || (c2702dD = j().d()) == null) {
            return;
        }
        List listA0 = c2765zH.a0();
        y(canvas, c2702dD, listA0.size(), new f0(listA0, this));
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        Paint paint = this.f95387A;
        paint.setColor(aVar.d(".price_info.unit_value"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        Paint paint2 = this.f95388B;
        paint2.setColor(aVar.d(".growth_info.positive"));
        paint2.setTextSize(this.f95387A.getTextSize());
        paint2.setAntiAlias(true);
        Paint paint3 = this.f95389C;
        paint3.setColor(aVar.d(".growth_info.negative"));
        paint3.setTextSize(this.f95387A.getTextSize());
        paint3.setAntiAlias(true);
        Paint paint4 = this.f95390D;
        paint4.setColor(aVar.d(".strategy.middle"));
        paint4.setTextSize(this.f95387A.getTextSize());
        paint4.setAntiAlias(true);
    }
}
