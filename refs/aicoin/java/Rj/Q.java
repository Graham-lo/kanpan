package Rj;

import android.view.View;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class Q implements View.OnClickListener {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ String f19233a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ S f19234b;

    public /* synthetic */ Q(String str, S s10) {
        this.f19233a = str;
        this.f19234b = s10;
    }

    @Override // android.view.View.OnClickListener
    public final void onClick(View view) {
        S.e(this.f19233a, this.f19234b, view);
    }
}
