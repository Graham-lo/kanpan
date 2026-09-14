package ek;

import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public final class I {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f93322a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final boolean f93323b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public boolean f93324c;

    public I(String str, boolean z10) {
        this.f93322a = str;
        this.f93323b = z10;
        this.f93324c = z10;
    }

    public /* synthetic */ I(String str, boolean z10, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, (i10 & 2) != 0 ? true : z10);
    }

    public final String a() {
        return this.f93322a;
    }

    public final boolean b() {
        return this.f93324c;
    }

    public final void c() {
        this.f93324c = this.f93323b;
    }

    public final void d(boolean z10) {
        this.f93324c = z10;
    }
}
