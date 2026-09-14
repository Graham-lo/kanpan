package Rj;

import Qf.InterfaceC2632j;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: renamed from: Rj.j0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2721j0 {

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public static final a f19432f = new a(null);

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f19433a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final C2715h0 f19434b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final String f19435c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final String f19436d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final InterfaceC2632j f19437e;

    /* JADX INFO: renamed from: Rj.j0$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public AbstractC2721j0(String str) {
        this.f19433a = str;
        C2715h0 c2715h0 = new C2715h0(str);
        this.f19434b = c2715h0;
        String strB = c2715h0.b(0);
        this.f19435c = strB == null ? "" : strB;
        String strB2 = c2715h0.b(1);
        this.f19436d = strB2 != null ? strB2 : "";
        this.f19437e = Qf.k.b(new C2718i0(this));
    }

    public static final String a(AbstractC2721j0 abstractC2721j0) {
        int iN0 = Ah.y.n0(abstractC2721j0.f19436d, "Range", 0, false, 6, null);
        Integer numValueOf = Integer.valueOf(iN0);
        if (iN0 <= 0) {
            numValueOf = null;
        }
        if (numValueOf != null) {
            return abstractC2721j0.f19436d.substring(0, iN0);
        }
        return null;
    }

    public final String b() {
        return this.f19436d;
    }

    public final String c() {
        return this.f19435c;
    }

    public final String d() {
        return this.f19433a;
    }

    public final C2715h0 e() {
        return this.f19434b;
    }

    public final String f() {
        return (String) this.f19437e.getValue();
    }
}
