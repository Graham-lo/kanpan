package p398sh.aicoin.kline.winrate;

import Dh.AbstractC1986i;
import Dh.C1979e0;
import Dh.O;
import Qf.H;
import Qf.s;
import Yf.l;
import java.util.List;
import p146gg.o;
import p167hg.M;

/* JADX INFO: loaded from: classes7.dex */
public final class e implements p398sh.aicoin.kline.winrate.d {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final p398sh.aicoin.kline.db.a f140695a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final g f140696b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final w f140697c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final m f140698d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final u f140699e;

    public static final class a extends l implements o {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public int f140700a;

        public a(Wf.d dVar) {
            super(2, dVar);
        }

        @Override // Yf.a
        public final Wf.d create(Object obj, Wf.d dVar) {
            return e.this.new a(dVar);
        }

        @Override // p146gg.o
        public final Object invoke(O o10, Wf.d dVar) {
            return ((a) create(o10, dVar)).invokeSuspend(H.f17640a);
        }

        @Override // Yf.a
        public final Object invokeSuspend(Object obj) throws Throwable {
            Object objE = Xf.c.e();
            int i10 = this.f140700a;
            if (i10 != 0) {
                if (i10 != 1) {
                    throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                }
                s.b(obj);
                return obj;
            }
            s.b(obj);
            u uVar = e.this.f140699e;
            H h10 = H.f17640a;
            this.f140700a = 1;
            Object objC = uVar.c(h10, this);
            return objC == objE ? objE : objC;
        }
    }

    public static final class b extends Yf.d {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public Object f140702a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public Object f140703b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public Object f140704c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public /* synthetic */ Object f140705d;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public int f140707f;

        public b(Wf.d dVar) {
            super(dVar);
        }

        @Override // Yf.a
        public final Object invokeSuspend(Object obj) {
            this.f140705d = obj;
            this.f140707f |= Integer.MIN_VALUE;
            return e.this.b(this);
        }
    }

    public static final class c extends l implements o {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public int f140708a;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final /* synthetic */ String f140710c;

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public c(String str, Wf.d dVar) {
            super(2, dVar);
            this.f140710c = str;
        }

        @Override // Yf.a
        public final Wf.d create(Object obj, Wf.d dVar) {
            return e.this.new c(this.f140710c, dVar);
        }

        @Override // p146gg.o
        public final Object invoke(O o10, Wf.d dVar) {
            return ((c) create(o10, dVar)).invokeSuspend(H.f17640a);
        }

        @Override // Yf.a
        public final Object invokeSuspend(Object obj) throws Throwable {
            Object objE = Xf.c.e();
            int i10 = this.f140708a;
            if (i10 != 0) {
                if (i10 != 1) {
                    throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                }
                s.b(obj);
                return obj;
            }
            s.b(obj);
            m mVar = e.this.f140698d;
            String str = this.f140710c;
            this.f140708a = 1;
            Object objC = mVar.c(str, this);
            return objC == objE ? objE : objC;
        }
    }

    public static final class d extends l implements o {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public int f140711a;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final /* synthetic */ String f140713c;

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public d(String str, Wf.d dVar) {
            super(2, dVar);
            this.f140713c = str;
        }

        @Override // Yf.a
        public final Wf.d create(Object obj, Wf.d dVar) {
            return e.this.new d(this.f140713c, dVar);
        }

        @Override // p146gg.o
        public final Object invoke(O o10, Wf.d dVar) {
            return ((d) create(o10, dVar)).invokeSuspend(H.f17640a);
        }

        @Override // Yf.a
        public final Object invokeSuspend(Object obj) throws Throwable {
            Object objE = Xf.c.e();
            int i10 = this.f140711a;
            if (i10 != 0) {
                if (i10 != 1) {
                    throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                }
                s.b(obj);
                return obj;
            }
            s.b(obj);
            w wVar = e.this.f140697c;
            String str = this.f140713c;
            this.f140711a = 1;
            Object objC = wVar.c(str, this);
            return objC == objE ? objE : objC;
        }
    }

    /* JADX INFO: renamed from: sh.aicoin.kline.winrate.e$e, reason: collision with other inner class name */
    public static final class C1578e extends Yf.d {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public Object f140714a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public /* synthetic */ Object f140715b;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public int f140717d;

        public C1578e(Wf.d dVar) {
            super(dVar);
        }

        @Override // Yf.a
        public final Object invokeSuspend(Object obj) {
            this.f140715b = obj;
            this.f140717d |= Integer.MIN_VALUE;
            return e.this.c(this);
        }
    }

    public e(p398sh.aicoin.kline.db.a aVar, g gVar, w wVar, m mVar, u uVar) {
        this.f140695a = aVar;
        this.f140696b = gVar;
        this.f140697c = wVar;
        this.f140698d = mVar;
        this.f140699e = uVar;
    }

    @Override // p398sh.aicoin.kline.winrate.d
    public Object a(Wf.d dVar) {
        return AbstractC1986i.g(C1979e0.b(), new a(null), dVar);
    }

    /* JADX WARN: Code duplicated, block: B:30:0x00a1  */
    /* JADX WARN: Code duplicated, block: B:32:0x00a9  */
    /* JADX WARN: Code duplicated, block: B:35:0x00b8  */
    /* JADX WARN: Code duplicated, block: B:38:0x00bf  */
    /* JADX WARN: Code duplicated, block: B:40:0x00cc  */
    /* JADX WARN: Code duplicated, block: B:42:0x00d2  */
    /* JADX WARN: Code duplicated, block: B:43:0x00d7  */
    /* JADX WARN: Code duplicated, block: B:46:0x00f2  */
    /* JADX WARN: Code duplicated, block: B:7:0x0013  */
    /* JADX WARN: Instruction removed from duplicated block: B:46:0x00f2, please report this as an issue */
    @Override // p398sh.aicoin.kline.winrate.d
    public Object b(Wf.d dVar) throws Throwable {
        b bVar;
        M m10;
        e eVar;
        M m11;
        M m12;
        e eVar2;
        p398sh.aicoin.app_base.net.response.a aVar;
        p254m.aicoin.base.logan.e eVar3;
        String str;
        Throwable thE;
        String message;
        List list;
        p398sh.aicoin.kline.db.a aVar2;
        List list2;
        M m13;
        if (dVar instanceof b) {
            bVar = (b) dVar;
            int i10 = bVar.f140707f;
            if ((i10 & Integer.MIN_VALUE) != 0) {
                bVar.f140707f = i10 - Integer.MIN_VALUE;
            } else {
                bVar = new b(dVar);
            }
        } else {
            bVar = new b(dVar);
        }
        Object objB = bVar.f140705d;
        Object objE = Xf.c.e();
        int i11 = bVar.f140707f;
        if (i11 == 0) {
            s.b(objB);
            m10 = new M();
            p398sh.aicoin.kline.db.a aVar3 = this.f140695a;
            bVar.f140702a = this;
            bVar.f140703b = m10;
            bVar.f140704c = m10;
            bVar.f140707f = 1;
            objB = aVar3.b(bVar);
            if (objB != objE) {
                eVar = this;
                m11 = m10;
            }
            return objE;
        }
        if (i11 == 1) {
            m10 = (M) bVar.f140704c;
            m11 = (M) bVar.f140703b;
            eVar = (e) bVar.f140702a;
            s.b(objB);
        } else {
            if (i11 == 2) {
                m12 = (M) bVar.f140703b;
                eVar2 = (e) bVar.f140702a;
                s.b(objB);
                aVar = (p398sh.aicoin.app_base.net.response.a) objB;
                if (aVar.i()) {
                    list = (List) aVar.d();
                    if (list != null) {
                        aVar2 = eVar2.f140695a;
                        bVar.f140702a = m12;
                        bVar.f140703b = list;
                        bVar.f140707f = 3;
                        if (aVar2.a(list, bVar) != objE) {
                            list2 = list;
                            m13 = m12;
                        }
                        return objE;
                    }
                } else {
                    if (aVar.e() != null) {
                        thE = aVar.e();
                        if (thE != null) {
                            message = thE.getMessage();
                        } else {
                            message = null;
                        }
                        lib.aicoin.utils.d.d("winrate", message);
                        eVar3 = p254m.aicoin.base.logan.e.f108272a;
                        str = "win rate config request failed errorCode=-1000";
                    } else {
                        int iH = aVar.h();
                        lib.aicoin.utils.d.d("winrate", aVar.g());
                        eVar3 = p254m.aicoin.base.logan.e.f108272a;
                        str = "win rate config request failed errorCode=" + iH;
                    }
                    eVar3.x(6, "klineWinRate", str, null);
                }
                m11 = m12;
                return m11.f97909a;
            }
            if (i11 != 3) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }
            list2 = (List) bVar.f140703b;
            m13 = (M) bVar.f140702a;
            s.b(objB);
        }
        m13.f97909a = list2;
        m12 = m13;
        m11 = m12;
        return m11.f97909a;
        m10.f97909a = objB;
        if (((List) m11.f97909a).isEmpty()) {
            g gVar = eVar.f140696b;
            H h10 = H.f17640a;
            bVar.f140702a = eVar;
            bVar.f140703b = m11;
            bVar.f140704c = null;
            bVar.f140707f = 2;
            objB = gVar.c(h10, bVar);
            if (objB != objE) {
                m12 = m11;
                eVar2 = eVar;
                aVar = (p398sh.aicoin.app_base.net.response.a) objB;
                if (aVar.i()) {
                    list = (List) aVar.d();
                    if (list != null) {
                        aVar2 = eVar2.f140695a;
                        bVar.f140702a = m12;
                        bVar.f140703b = list;
                        bVar.f140707f = 3;
                        if (aVar2.a(list, bVar) != objE) {
                            list2 = list;
                            m13 = m12;
                            m13.f97909a = list2;
                            m12 = m13;
                        }
                    }
                } else {
                    if (aVar.e() != null) {
                        thE = aVar.e();
                        if (thE != null) {
                            message = thE.getMessage();
                        } else {
                            message = null;
                        }
                        lib.aicoin.utils.d.d("winrate", message);
                        eVar3 = p254m.aicoin.base.logan.e.f108272a;
                        str = "win rate config request failed errorCode=-1000";
                    } else {
                        int iH2 = aVar.h();
                        lib.aicoin.utils.d.d("winrate", aVar.g());
                        eVar3 = p254m.aicoin.base.logan.e.f108272a;
                        str = "win rate config request failed errorCode=" + iH2;
                    }
                    eVar3.x(6, "klineWinRate", str, null);
                }
                m11 = m12;
            }
            return objE;
        }
        return m11.f97909a;
    }

    /* JADX WARN: Code duplicated, block: B:7:0x0013  */
    /* JADX WARN: Code restructure failed: missing block: B:25:0x006b, code lost:
    
        if (r2.a(r7, r0) == r1) goto L26;
     */
    @Override // p398sh.aicoin.kline.winrate.d
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    public java.lang.Object c(Wf.d r7) throws java.lang.Throwable {
        /*
            r6 = this;
            boolean r0 = r7 instanceof p398sh.aicoin.kline.winrate.e.C1578e
            if (r0 == 0) goto L13
            r0 = r7
            sh.aicoin.kline.winrate.e$e r0 = (p398sh.aicoin.kline.winrate.e.C1578e) r0
            int r1 = r0.f140717d
            r2 = -2147483648(0xffffffff80000000, float:-0.0)
            r3 = r1 & r2
            if (r3 == 0) goto L13
            int r1 = r1 - r2
            r0.f140717d = r1
            goto L18
        L13:
            sh.aicoin.kline.winrate.e$e r0 = new sh.aicoin.kline.winrate.e$e
            r0.<init>(r7)
        L18:
            java.lang.Object r7 = r0.f140715b
            java.lang.Object r1 = Xf.c.e()
            int r2 = r0.f140717d
            r3 = 2
            r4 = 1
            if (r2 == 0) goto L3d
            if (r2 == r4) goto L35
            if (r2 != r3) goto L2d
            Qf.s.b(r7)
            goto Lbe
        L2d:
            java.lang.IllegalStateException r7 = new java.lang.IllegalStateException
            java.lang.String r0 = "call to 'resume' before 'invoke' with coroutine"
            r7.<init>(r0)
            throw r7
        L35:
            java.lang.Object r2 = r0.f140714a
            sh.aicoin.kline.winrate.e r2 = (p398sh.aicoin.kline.winrate.e) r2
            Qf.s.b(r7)
            goto L50
        L3d:
            Qf.s.b(r7)
            sh.aicoin.kline.winrate.g r7 = r6.f140696b
            Qf.H r2 = Qf.H.f17640a
            r0.f140714a = r6
            r0.f140717d = r4
            java.lang.Object r7 = r7.c(r2, r0)
            if (r7 != r1) goto L4f
            goto L6d
        L4f:
            r2 = r6
        L50:
            sh.aicoin.app_base.net.response.a r7 = (p398sh.aicoin.app_base.net.response.a) r7
            boolean r4 = r7.i()
            r5 = 0
            if (r4 == 0) goto L6e
            java.lang.Object r7 = r7.d()
            java.util.List r7 = (java.util.List) r7
            if (r7 == 0) goto Lbe
            sh.aicoin.kline.db.a r2 = r2.f140695a
            r0.f140714a = r5
            r0.f140717d = r3
            java.lang.Object r7 = r2.a(r7, r0)
            if (r7 != r1) goto Lbe
        L6d:
            return r1
        L6e:
            java.lang.Throwable r0 = r7.e()
            java.lang.String r1 = "win rate config refresh failed errorCode="
            java.lang.String r2 = "klineWinRate"
            r3 = 6
            java.lang.String r4 = "winrate"
            if (r0 == 0) goto La1
            java.lang.Throwable r7 = r7.e()
            if (r7 == 0) goto L86
            java.lang.String r7 = r7.getMessage()
            goto L87
        L86:
            r7 = r5
        L87:
            lib.aicoin.utils.d.d(r4, r7)
            m.aicoin.base.logan.e r7 = p254m.aicoin.base.logan.e.f108272a
            java.lang.StringBuilder r0 = new java.lang.StringBuilder
            r0.<init>()
            r0.append(r1)
            r1 = -1000(0xfffffffffffffc18, float:NaN)
            r0.append(r1)
            java.lang.String r0 = r0.toString()
        L9d:
            r7.x(r3, r2, r0, r5)
            goto Lbe
        La1:
            int r0 = r7.h()
            java.lang.String r7 = r7.g()
            lib.aicoin.utils.d.d(r4, r7)
            m.aicoin.base.logan.e r7 = p254m.aicoin.base.logan.e.f108272a
            java.lang.StringBuilder r4 = new java.lang.StringBuilder
            r4.<init>()
            r4.append(r1)
            r4.append(r0)
            java.lang.String r0 = r4.toString()
            goto L9d
        Lbe:
            Qf.H r7 = Qf.H.f17640a
            return r7
        */
        throw new UnsupportedOperationException("Method not decompiled: p398sh.aicoin.kline.winrate.e.c(Wf.d):java.lang.Object");
    }

    @Override // p398sh.aicoin.kline.winrate.d
    public Object d(String str, Wf.d dVar) {
        return AbstractC1986i.g(C1979e0.b(), new d(str, null), dVar);
    }

    @Override // p398sh.aicoin.kline.winrate.d
    public Object e(String str, Wf.d dVar) {
        return AbstractC1986i.g(C1979e0.b(), new c(str, null), dVar);
    }
}
