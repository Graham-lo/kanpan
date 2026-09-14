package Rj;

import android.view.View;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class P implements View.OnClickListener {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ String f19230a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ S f19231b;

    public /* synthetic */ P(String str, S s10) {
        this.f19230a = str;
        this.f19231b = s10;
    }

    @Override // android.view.View.OnClickListener
    public final void onClick(View view) {
        S.d(this.f19230a, this.f19231b, view);
    }
}
