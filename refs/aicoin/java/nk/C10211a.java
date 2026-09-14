package nk;

import java.util.LinkedList;

/* JADX INFO: renamed from: nk.a, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public class C10211a implements p047c2.d {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final LinkedList f134193a = new LinkedList();

    @Override // p047c2.d
    public boolean a(Object obj) {
        synchronized (this.f134193a) {
            this.f134193a.push(obj);
        }
        return true;
    }

    @Override // p047c2.d
    public Object b() {
        synchronized (this.f134193a) {
            try {
                if (this.f134193a.isEmpty()) {
                    return null;
                }
                return this.f134193a.pop();
            } catch (Throwable th2) {
                throw th2;
            }
        }
    }

    public void c() {
        synchronized (this.f134193a) {
            this.f134193a.clear();
        }
    }
}
