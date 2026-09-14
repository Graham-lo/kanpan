package sp.aicoin_kline.core.indicator.config;

import Qf.InterfaceC2632j;
import android.content.SharedPreferences;
import com.tencent.android.tpush.common.MessageKey;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public abstract class F {

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public static final a f142562k = new a(null);

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final InterfaceC2632j f142563a = Qf.k.b(new ek.q(this));

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final InterfaceC2632j f142564b = Qf.k.b(new ek.r(this));

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final InterfaceC2632j f142565c = Qf.k.b(new ek.s(this));

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final InterfaceC2632j f142566d = Qf.k.b(new ek.t(this));

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final InterfaceC2632j f142567e = Qf.k.b(new ek.u(this));

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final SharedPreferences f142568f = KLineManager.f142490O.a().i().getApplicationContext().getSharedPreferences("soso_kline_indicator_param", 0);

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final String f142569g = n() + "_indi_value_";

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final String f142570h = n() + "_decindi_value_";

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final String f142571i = n() + "_indi_visible_";

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public final String f142572j = n() + "_indi_color_";

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public static final ek.m[] a(F f10) {
        ek.m[] mVarArrU = f10.u();
        int length = mVarArrU.length;
        int i10 = 0;
        int i11 = 0;
        while (i10 < length) {
            ek.m mVar = mVarArrU[i10];
            int i12 = i11 + 1;
            String str = f10.f142572j + i11;
            if (f10.f142568f.contains(str)) {
                mVar.d(f10.f142568f.getInt(str + MessageKey.NOTIFICATION_COLOR, -1));
                mVar.e(f10.f142568f.getFloat(str + "size", 2.0f));
            }
            i10++;
            i11 = i12;
        }
        return mVarArrU;
    }

    public static final ek.w[] d(F f10) {
        return f10.b();
    }

    public static final ek.w[] f(F f10) {
        return f10.b();
    }

    public static final ek.I[] g(F f10) {
        return f10.e();
    }

    public static final ek.I[] h(F f10) {
        return f10.e();
    }

    public final ek.w[] b() {
        ek.w[] wVarArrV = v();
        for (ek.w wVar : wVarArrV) {
            if (wVar.e() > 0) {
                String str = this.f142570h + wVar.c();
                if (this.f142568f.contains(str)) {
                    wVar.i(this.f142568f.getFloat(str, wVar.a()));
                }
            } else {
                String str2 = this.f142569g + wVar.c();
                if (this.f142568f.contains(str2)) {
                    wVar.j(this.f142568f.getInt(str2, wVar.a()));
                }
            }
        }
        return wVarArrV;
    }

    public void c(ChartIndicatorSetting chartIndicatorSetting) {
    }

    public final ek.I[] e() {
        ek.I[] iArrW = w();
        int length = iArrW.length;
        int i10 = 0;
        int i11 = 0;
        while (i10 < length) {
            ek.I i12 = iArrW[i10];
            int i13 = i11 + 1;
            String str = this.f142571i + i11;
            if (this.f142568f.contains(str)) {
                i12.d(this.f142568f.getBoolean(str, true));
            }
            i10++;
            i11 = i13;
        }
        return iArrW;
    }

    public ChartIndicatorSetting i() {
        return null;
    }

    public ChartIndicatorSetting j(boolean z10) {
        return null;
    }

    public final ek.m[] k() {
        return (ek.m[]) this.f142567e.getValue();
    }

    public final ek.w[] l() {
        return (ek.w[]) this.f142566d.getValue();
    }

    public int m() {
        return 0;
    }

    public abstract String n();

    public final ek.w[] o() {
        return (ek.w[]) this.f142564b.getValue();
    }

    public final ek.I[] p() {
        return (ek.I[]) this.f142563a.getValue();
    }

    public abstract int q();

    public final ek.I[] r() {
        return (ek.I[]) this.f142565c.getValue();
    }

    public abstract boolean s();

    public boolean t() {
        return false;
    }

    public abstract ek.m[] u();

    public abstract ek.w[] v();

    public abstract ek.I[] w();

    public final void x() {
        for (ek.I i10 : r()) {
            i10.c();
        }
        for (ek.m mVar : k()) {
            mVar.c();
        }
        for (ek.w wVar : l()) {
            wVar.h();
        }
    }

    public final void y() {
        ek.I[] iArrR = r();
        SharedPreferences.Editor editorEdit = this.f142568f.edit();
        int length = iArrR.length;
        int i10 = 0;
        int i11 = 0;
        int i12 = 0;
        while (i11 < length) {
            editorEdit.putBoolean(this.f142571i + i12, iArrR[i11].b());
            i11++;
            i12++;
        }
        editorEdit.apply();
        ek.w[] wVarArrL = l();
        SharedPreferences.Editor editorEdit2 = this.f142568f.edit();
        for (ek.w wVar : wVarArrL) {
            if (wVar.e() > 0) {
                editorEdit2.putFloat(this.f142570h + wVar.c(), wVar.b());
            } else {
                editorEdit2.putInt(this.f142569g + wVar.c(), wVar.g());
            }
        }
        editorEdit2.apply();
        ek.m[] mVarArrK = k();
        SharedPreferences.Editor editorEdit3 = this.f142568f.edit();
        int length2 = mVarArrK.length;
        int i13 = 0;
        while (i10 < length2) {
            ek.m mVar = mVarArrK[i10];
            editorEdit3.putInt(this.f142572j + i13 + MessageKey.NOTIFICATION_COLOR, mVar.a());
            editorEdit3.putFloat(this.f142572j + i13 + "size", mVar.b());
            i10++;
            i13++;
        }
        editorEdit3.apply();
    }
}
