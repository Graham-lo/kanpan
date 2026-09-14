package mk;

import android.content.SharedPreferences;
import java.util.LinkedHashMap;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public abstract class b extends a {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final SharedPreferences f133590b = KLineManager.f142490O.a().i().getSharedPreferences("ai_kline_color_pref", 0);

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final LinkedHashMap f133591c = new LinkedHashMap();

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final int f133592d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final int f133593e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final int f133594f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final int f133595g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final int f133596h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final int f133597i;

    public b() {
        C();
        D();
        this.f133592d = -3402732;
        this.f133593e = -14046130;
        this.f133594f = -3402732;
        this.f133595g = -14046130;
        this.f133596h = -7829368;
        this.f133597i = -15302271;
    }

    public abstract int A();

    public abstract int B();

    public abstract void C();

    public final void D() {
        a(".main_red.color", this.f133590b.getInt(".main_red.color", d(".main_red.color")));
        a(".main_green.color", this.f133590b.getInt(".main_green.color", d(".main_green.color")));
    }

    @Override // mk.a
    public void a(String str, int i10) {
        this.f133591c.put(str, Integer.valueOf(i10));
    }

    @Override // mk.a
    public int d(String str) {
        Integer num = (Integer) this.f133591c.get(str);
        if (num != null) {
            return num.intValue();
        }
        return 0;
    }

    @Override // mk.a
    public int g(int i10) {
        return 0;
    }

    @Override // mk.a
    public int l() {
        KLineManager.a aVar = KLineManager.f142490O;
        if (aVar.a().T() && aVar.a().V()) {
            return y();
        }
        return z();
    }

    @Override // mk.a
    public int m() {
        return KLineManager.f142490O.a().V() ? A() : B();
    }

    @Override // mk.a
    public int q() {
        KLineManager.a aVar = KLineManager.f142490O;
        if (aVar.a().T() && aVar.a().V()) {
            return z();
        }
        return y();
    }

    @Override // mk.a
    public int r() {
        return KLineManager.f142490O.a().V() ? B() : A();
    }

    @Override // mk.a
    public int u(int i10) {
        return 0;
    }

    @Override // mk.a
    public int v() {
        return 0;
    }

    public final SharedPreferences x() {
        return this.f133590b;
    }

    public abstract int y();

    public abstract int z();
}
