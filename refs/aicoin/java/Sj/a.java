package Sj;

import java.util.ArrayList;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public final class a extends ArrayList {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final C0293a f20758a = new C0293a(null);

    /* JADX INFO: renamed from: Sj.a$a, reason: collision with other inner class name */
    public static final class C0293a {
        public C0293a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public /* bridge */ int a() {
        return super.size();
    }

    public /* bridge */ Object d(int i10) {
        return super.remove(i10);
    }

    @Override // java.util.ArrayList, java.util.AbstractList, java.util.List
    public final /* bridge */ Object remove(int i10) {
        return d(i10);
    }

    @Override // java.util.ArrayList, java.util.AbstractCollection, java.util.Collection, java.util.List
    public final /* bridge */ int size() {
        return a();
    }
}
