package ek;

import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public final class w {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f93337a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final p292ng.g f93338b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final int f93339c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final boolean f93340d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final int f93341e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public int f93342f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public float f93343g;

    public w(String str, p292ng.g gVar, int i10, boolean z10, int i11) {
        this.f93337a = str;
        this.f93338b = gVar;
        this.f93339c = i10;
        this.f93340d = z10;
        this.f93341e = i11;
        this.f93342f = i10;
        this.f93343g = i10;
    }

    public /* synthetic */ w(String str, p292ng.g gVar, int i10, boolean z10, int i11, int i12, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, gVar, i10, (i12 & 8) != 0 ? true : z10, (i12 & 16) != 0 ? 0 : i11);
    }

    public final int a() {
        return this.f93339c;
    }

    public final float b() {
        return this.f93343g;
    }

    public final String c() {
        return this.f93337a;
    }

    public final p292ng.g d() {
        return this.f93338b;
    }

    public final int e() {
        return this.f93341e;
    }

    public final boolean f() {
        return this.f93340d;
    }

    public final int g() {
        return this.f93342f;
    }

    public final void h() {
        j(this.f93339c);
        i(this.f93339c);
    }

    public final void i(float f10) {
        if (this.f93338b.k() > f10 || this.f93338b.o() < f10) {
            return;
        }
        this.f93343g = f10;
    }

    public final void j(int i10) {
        if (this.f93338b.w(i10)) {
            this.f93342f = i10;
        }
    }
}
