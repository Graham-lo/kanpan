package Rj;

import java.util.Map;
import p167hg.AbstractC7609s;

/* JADX INFO: renamed from: Rj.d0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2703d0 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final C2703d0 f19361a = new C2703d0();

    public final boolean a(String str, Map map) {
        return AbstractC7609s.f(str, "main_script_indicator") || !AbstractC7609s.f(map.get(str), Boolean.FALSE);
    }

    public final boolean b(String str, Map map) {
        return str == null || str.length() == 0 || !AbstractC7609s.f(map.get(str), Boolean.FALSE);
    }
}
