package fk;

import Rj.AbstractC2693a;
import Rj.C2702d;
import Rj.C2732n;
import Sf.AbstractC2803q;
import android.content.Context;
import android.content.res.Resources;
import android.graphics.Canvas;
import android.graphics.Paint;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.v, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7396v extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final Paint f95572A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public String f95573B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public String f95574C;

    public C7396v(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95572A = new Paint(A());
        this.f95573B = "";
        this.f95574C = "";
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        String str;
        C2702d c2702dD = j().d();
        if (c2702dD == null || this.f95573B.length() == 0) {
            return;
        }
        String strD = Sj.c.f20766a.d();
        if (strD == null || strD.length() == 0) {
            str = this.f95573B;
        } else {
            str = this.f95573B + ": " + strD;
        }
        z(canvas, c2702dD, AbstractC2803q.e(new AbstractC2693a.b(str, this.f95572A, false, true, this.f95574C, false, 36, null)));
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        String string;
        Resources resources;
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        this.f95572A.set(A());
        KLineManager.a aVar2 = KLineManager.f142490O;
        Context contextW = aVar2.a().w();
        if (contextW == null || (resources = contextW.getResources()) == null || (string = resources.getString(R.string.kline_het_map__title)) == null) {
            string = aVar2.a().i().getResources().getString(R.string.kline_het_map__title);
        }
        this.f95573B = string;
        this.f95574C = "liqheatmap";
    }
}
