package ek;

import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public final class m {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f93325a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final int f93326b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final float f93327c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public int f93328d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public float f93329e;

    public m(String str, int i10, float f10) {
        this.f93325a = str;
        this.f93326b = i10;
        this.f93327c = f10;
        this.f93328d = i10;
        this.f93329e = f10;
    }

    public /* synthetic */ m(String str, int i10, float f10, int i11, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, i10, (i11 & 4) != 0 ? 2.0f : f10);
    }

    public final int a() {
        return this.f93328d;
    }

    public final float b() {
        return this.f93329e;
    }

    public final void c() {
        this.f93328d = this.f93326b;
        this.f93329e = this.f93327c;
    }

    public final void d(int i10) {
        this.f93328d = i10;
    }

    public final void e(float f10) {
        this.f93329e = f10;
    }
}
