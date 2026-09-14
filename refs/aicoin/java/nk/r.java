package nk;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class r {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public List f134240a;

    public final class a implements b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public int f134241a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final ArrayList f134242b = new ArrayList();

        public a() {
        }

        @Override // nk.r.b
        public void b() {
            List list = r.this.f134240a;
            r.this.f134240a = this.f134242b;
            if (list != null) {
                Iterator it = list.iterator();
                while (it.hasNext()) {
                    ((q) it.next()).f();
                }
            }
        }

        @Override // nk.r.b
        public b d() {
            this.f134241a = 0;
            return this;
        }

        @Override // nk.r.b
        public b e(q qVar) {
            int i10 = this.f134241a + 1;
            this.f134241a = i10;
            qVar.h(i10);
            this.f134242b.add(qVar);
            return this;
        }
    }

    public interface b {
        void b();

        b d();

        b e(q qVar);
    }

    public final b c() {
        return new a();
    }

    public final Object d(int i10, int i11) {
        List<q> list = this.f134240a;
        if (list != null && !list.isEmpty()) {
            float f10 = i10;
            float f11 = i11;
            q qVar = null;
            q qVar2 = null;
            for (q qVar3 : list) {
                if (qVar == null) {
                    if (qVar3.b(f10, f11)) {
                        qVar = qVar3;
                    } else if (qVar3.c(f10, f11) && (qVar2 == null || qVar3.d() > qVar2.d())) {
                        qVar2 = qVar3;
                    }
                } else if (qVar3.b(f10, f11) && qVar3.d() > qVar.d()) {
                    qVar = qVar3;
                }
            }
            if (qVar != null) {
                return qVar.e();
            }
            if (qVar2 != null) {
                return qVar2.e();
            }
        }
        return null;
    }
}
