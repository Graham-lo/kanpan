package Rj;

import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: Rj.h0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2715h0 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final ArrayList f19417a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final List f19418b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final String f19419c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final int f19420d;

    public C2715h0(String str) {
        List listM0 = Ah.y.M0(str, new String[]{"."}, false, 0, 6, null);
        this.f19418b = listM0;
        ArrayList arrayList = new ArrayList();
        int size = listM0.size();
        if (size > 0) {
            String str2 = (String) listM0.get(0);
            arrayList.add(str2);
            StringBuilder sb2 = new StringBuilder(str2);
            for (int i10 = 1; i10 < size; i10++) {
                sb2.append(".");
                sb2.append((String) this.f19418b.get(i10));
                arrayList.add(sb2.toString());
            }
        }
        this.f19417a = arrayList;
        String str3 = (String) Sf.z.D0(arrayList);
        this.f19419c = str3 == null ? "" : str3;
        this.f19420d = this.f19418b.size();
    }

    public final String a(int i10) {
        return (String) Sf.z.r0(this.f19418b, i10);
    }

    public final String b(int i10) {
        return (String) Sf.z.r0(this.f19417a, i10);
    }
}
