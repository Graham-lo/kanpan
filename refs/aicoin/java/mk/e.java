package mk;

import android.content.SharedPreferences;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class e {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final e f133635a = new e();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final SharedPreferences f133636b = KLineManager.f142490O.a().i().getSharedPreferences("ai_kline_color_pref", 0);

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final d f133637c = new d();

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static final c f133638d = new c();

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static final String[] f133639e = {".main_red.color", ".main_green.color", ".drawing.line", ".drawing.text", ".drawing.bg", ".background_plot.color", "indicator_line_color_0", "indicator_line_color_1", "indicator_line_color_2", "indicator_line_color_3", "indicator_line_color_4", "indicator_line_color_5"};

    public final a a() {
        c cVar = new c();
        for (String str : f133639e) {
            f133635a.getClass();
            cVar.a(str, f133636b.getInt("dark-" + str, f133638d.d(str)));
        }
        return cVar;
    }

    public final a b() {
        d dVar = new d();
        for (String str : f133639e) {
            f133635a.getClass();
            dVar.a(str, f133636b.getInt("light-" + str, f133637c.d(str)));
        }
        return dVar;
    }

    public final int c() {
        return f133636b.getInt("light-.main_candle_green.color", -13192617);
    }

    public final int d() {
        return f133636b.getInt("light-.main_candle_red.color", -1686190);
    }

    public final void e(int i10) {
        f133636b.edit().putInt("light-.main_candle_green.color", i10).apply();
    }

    public final void f(int i10) {
        f133636b.edit().putInt("dark-.main_candle_green.color", i10).apply();
    }

    public final void g(int i10) {
        f133636b.edit().putInt("light-.main_candle_red.color", i10).apply();
    }

    public final void h(int i10) {
        f133636b.edit().putInt("dark-.main_candle_red.color", i10).apply();
    }
}
