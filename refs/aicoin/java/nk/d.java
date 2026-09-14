package nk;

import ck.B;
import ck.C;
import ck.C6302a;
import ck.C6307f;
import ck.C6308g;
import ck.C6310i;
import ck.C6311j;
import ck.C6312k;
import ck.C6313l;
import ck.E;
import ck.F;
import ck.G;
import ck.H;
import ck.J;
import ck.K;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.drawing.DrawingItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class d {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final d f134196a = new d();

    public final String a(int i10) {
        switch (i10) {
            case 1:
                return "CHoriSegLineObject";
            case 2:
                return "CHoriStraightLineObject";
            case 3:
                return "CHoriRayLineObject";
            case 4:
                return "CVertiStraightLineObject";
            case 5:
                return "CPriceLineObject";
            case 6:
                return "CFibRetraceObject";
            case 7:
                return "CSegLineObject";
            case 8:
                return "CStraightLineObject";
            case 9:
                return "CRayLineObject";
            case 10:
                return "CArrowLineObject";
            case 11:
                return "CTriParallelLineObject";
            case 12:
                return "CRectangleObject";
            case 13:
                return "CPriceDateRulerObject";
            case 14:
                return "CFibSpiralObject";
            case 15:
                return "CFibFansObject";
            case 16:
                return "CFibExtensionObject";
            case 17:
                return "CFibRetraceSegLineObject";
            case 18:
                return "CBandLineObject";
            case 19:
                return "CBandSegLineObject";
            default:
                return "CEmptyObject";
        }
    }

    public final int b(String str) {
        switch (str.hashCode()) {
            case -1891717230:
                return !str.equals("CFibRetraceSegLineObject") ? 0 : 17;
            case -1864460939:
                return !str.equals("CFibRetraceObject") ? 0 : 6;
            case -1791960455:
                return !str.equals("CArrowLineObject") ? 0 : 10;
            case -1785633490:
                return !str.equals("CHoriStraightLineObject") ? 0 : 2;
            case -1631049823:
                return !str.equals("CPriceDateRulerObject") ? 0 : 13;
            case -1576499271:
                return !str.equals("CPriceLineObject") ? 0 : 5;
            case -1570470804:
                return !str.equals("CFibSpiralObject") ? 0 : 14;
            case -1516759383:
                str.equals("CEmptyObject");
                return 0;
            case -1407425220:
                return !str.equals("CHoriRayLineObject") ? 0 : 3;
            case -964927739:
                return !str.equals("CSegLineObject") ? 0 : 7;
            case -283576629:
                return !str.equals("CRectangleObject") ? 0 : 12;
            case 278879298:
                return !str.equals("CPolylineObject") ? 0 : 20;
            case 282550274:
                return !str.equals("CFibExtensionObject") ? 0 : 16;
            case 826758298:
                return !str.equals("CRayLineObject") ? 0 : 9;
            case 827023504:
                return !str.equals("CStraightLineObject") ? 0 : 8;
            case 942058010:
                str.equals("CMagnifierObject");
                return 0;
            case 1037884066:
                return !str.equals("CVertiStraightLineObject") ? 0 : 4;
            case 1095856039:
                return !str.equals("CHoriSegLineObject") ? 0 : 1;
            case 1759461627:
                return !str.equals("CFibFansObject") ? 0 : 15;
            case 2071238210:
                return !str.equals("CTriParallelLineObject") ? 0 : 11;
            default:
                return 0;
        }
    }

    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    public final ck.w c(DrawingItem drawingItem) {
        String name = drawingItem.getName();
        switch (name.hashCode()) {
            case -1891717230:
                if (name.equals("CFibRetraceSegLineObject")) {
                    return new ck.m(drawingItem);
                }
                break;
            case -1864460939:
                if (name.equals("CFibRetraceObject")) {
                    return new C6313l(drawingItem);
                }
                break;
            case -1824047412:
                if (name.equals("CMWObject")) {
                    return new K(drawingItem);
                }
                break;
            case -1791960455:
                if (name.equals("CArrowLineObject")) {
                    return new C6302a(drawingItem);
                }
                break;
            case -1785633490:
                if (name.equals("CHoriStraightLineObject")) {
                    return new ck.n(drawingItem);
                }
                break;
            case -1690582726:
                if (name.equals("CEllipseObject")) {
                    return new C6307f(drawingItem);
                }
                break;
            case -1669482373:
                if (name.equals("CParallelogramObject")) {
                    return new ck.u(drawingItem);
                }
                break;
            case -1631049823:
                if (name.equals("CPriceDateRulerObject")) {
                    return new E(drawingItem);
                }
                break;
            case -1576499271:
                if (name.equals("CPriceLineObject")) {
                    return new ck.y(drawingItem);
                }
                break;
            case -1570470804:
                if (name.equals("CFibSpiralObject")) {
                    return new C6310i(drawingItem);
                }
                break;
            case -1516759383:
                if (name.equals("CEmptyObject")) {
                    return new C6308g(drawingItem);
                }
                break;
            case -1407425220:
                if (name.equals("CHoriRayLineObject")) {
                    return new ck.A(drawingItem);
                }
                break;
            case -964927739:
                if (name.equals("CSegLineObject")) {
                    return new C(drawingItem);
                }
                break;
            case -763701555:
                if (name.equals("CEightWavesObject")) {
                    return new K(drawingItem);
                }
                break;
            case -717675665:
                if (name.equals("CTextObject")) {
                    return new G(drawingItem);
                }
                break;
            case -583858256:
                if (name.equals("CMasterMaskObject")) {
                    return new ck.p(drawingItem);
                }
                break;
            case -283576629:
                if (name.equals("CRectangleObject")) {
                    return new B(drawingItem);
                }
                break;
            case 32784196:
                if (name.equals("CBiParallelLineObject")) {
                    return new ck.t(drawingItem);
                }
                break;
            case 90159012:
                if (name.equals("CFiveWavesObject")) {
                    return new K(drawingItem);
                }
                break;
            case 165767052:
                if (name.equals("CBiParallelRayLineObject")) {
                    return new ck.s(drawingItem);
                }
                break;
            case 282550274:
                if (name.equals("CFibExtensionObject")) {
                    return new C6311j(drawingItem);
                }
                break;
            case 549884058:
                if (name.equals("CPeriodLinesObject")) {
                    return new ck.x(drawingItem);
                }
                break;
            case 633426526:
                if (name.equals("CThreeWavesObject")) {
                    return new K(drawingItem);
                }
                break;
            case 826758298:
                if (name.equals("CRayLineObject")) {
                    return new ck.A(drawingItem);
                }
                break;
            case 827023504:
                if (name.equals("CStraightLineObject")) {
                    return new F(drawingItem);
                }
                break;
            case 942058010:
                if (name.equals("CMagnifierObject")) {
                    return new C6308g(drawingItem);
                }
                break;
            case 1037884066:
                if (name.equals("CVertiStraightLineObject")) {
                    return new J(drawingItem);
                }
                break;
            case 1095856039:
                if (name.equals("CHoriSegLineObject")) {
                    return new C(drawingItem);
                }
                break;
            case 1197575818:
                if (name.equals("CTriangleObject")) {
                    return new H(drawingItem);
                }
                break;
            case 1759461627:
                if (name.equals("CFibFansObject")) {
                    return new C6312k(drawingItem);
                }
                break;
            case 2071238210:
                if (name.equals("CTriParallelLineObject")) {
                    return new ck.r(drawingItem);
                }
                break;
        }
        return new C6308g(drawingItem);
    }

    public final int d(String str) {
        switch (str.hashCode()) {
            case -1891717230:
                return !str.equals("CFibRetraceSegLineObject") ? 0 : 2;
            case -1864460939:
                return !str.equals("CFibRetraceObject") ? 0 : 2;
            case -1791960455:
                return !str.equals("CArrowLineObject") ? 0 : 2;
            case -1785633490:
                return !str.equals("CHoriStraightLineObject") ? 0 : 1;
            case -1631049823:
                return !str.equals("CPriceDateRulerObject") ? 0 : 2;
            case -1576499271:
                return !str.equals("CPriceLineObject") ? 0 : 1;
            case -1570470804:
                return !str.equals("CFibSpiralObject") ? 0 : 2;
            case -1516759383:
                str.equals("CEmptyObject");
                return 0;
            case -1407425220:
                return !str.equals("CHoriRayLineObject") ? 0 : 2;
            case -964927739:
                return !str.equals("CSegLineObject") ? 0 : 2;
            case -283576629:
                return !str.equals("CRectangleObject") ? 0 : 4;
            case 278879298:
                return !str.equals("CPolylineObject") ? 0 : 3;
            case 282550274:
                return !str.equals("CFibExtensionObject") ? 0 : 3;
            case 826758298:
                return !str.equals("CRayLineObject") ? 0 : 2;
            case 827023504:
                return !str.equals("CStraightLineObject") ? 0 : 2;
            case 942058010:
                str.equals("CMagnifierObject");
                return 0;
            case 1037884066:
                return !str.equals("CVertiStraightLineObject") ? 0 : 1;
            case 1095856039:
                return !str.equals("CHoriSegLineObject") ? 0 : 2;
            case 1759461627:
                return !str.equals("CFibFansObject") ? 0 : 2;
            case 2071238210:
                return !str.equals("CTriParallelLineObject") ? 0 : 3;
            default:
                return 0;
        }
    }

    public final boolean e(String str) {
        return AbstractC7609s.f(str, "CRectangleObject") || AbstractC7609s.f(str, "CPriceDateRulerObject");
    }

    /* JADX WARN: Can't fix incorrect switch cases order, some code will duplicate */
    /* JADX WARN: Code duplicated, block: B:94:0x0138  */
    public final void f(String str) {
        int i10;
        String str2;
        KLineManager kLineManagerA = KLineManager.f142490O.a();
        switch (str.hashCode()) {
            case -1891717230:
                if (!str.equals("CFibRetraceSegLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 17;
                }
                break;
            case -1864460939:
                if (!str.equals("CFibRetraceObject")) {
                    i10 = 0;
                } else {
                    i10 = 6;
                }
                break;
            case -1824047412:
                str2 = "CMWObject";
                str.equals(str2);
                i10 = 0;
                break;
            case -1791960455:
                if (!str.equals("CArrowLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 10;
                }
                break;
            case -1785633490:
                if (!str.equals("CHoriStraightLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 2;
                }
                break;
            case -1690582726:
                str2 = "CEllipseObject";
                str.equals(str2);
                i10 = 0;
                break;
            case -1669482373:
                str2 = "CParallelogramObject";
                str.equals(str2);
                i10 = 0;
                break;
            case -1631049823:
                if (!str.equals("CPriceDateRulerObject")) {
                    i10 = 0;
                } else {
                    i10 = 13;
                }
                break;
            case -1576499271:
                if (!str.equals("CPriceLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 5;
                }
                break;
            case -1570470804:
                if (!str.equals("CFibSpiralObject")) {
                    i10 = 0;
                } else {
                    i10 = 14;
                }
                break;
            case -1516759383:
                str2 = "CEmptyObject";
                str.equals(str2);
                i10 = 0;
                break;
            case -1407425220:
                if (!str.equals("CHoriRayLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 3;
                }
                break;
            case -964927739:
                if (!str.equals("CSegLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 7;
                }
                break;
            case -763701555:
                str2 = "CEightWavesObject";
                str.equals(str2);
                i10 = 0;
                break;
            case -717675665:
                str2 = "CTextObject";
                str.equals(str2);
                i10 = 0;
                break;
            case -583858256:
                str2 = "CMasterMaskObject";
                str.equals(str2);
                i10 = 0;
                break;
            case -283576629:
                if (!str.equals("CRectangleObject")) {
                    i10 = 0;
                } else {
                    i10 = 12;
                }
                break;
            case -87656565:
                if (!str.equals("CBandLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 18;
                }
                break;
            case 32784196:
                str2 = "CBiParallelLineObject";
                str.equals(str2);
                i10 = 0;
                break;
            case 90159012:
                str2 = "CFiveWavesObject";
                str.equals(str2);
                i10 = 0;
                break;
            case 165767052:
                str2 = "CBiParallelRayLineObject";
                str.equals(str2);
                i10 = 0;
                break;
            case 282550274:
                if (!str.equals("CFibExtensionObject")) {
                    i10 = 0;
                } else {
                    i10 = 16;
                }
                break;
            case 549884058:
                str2 = "CPeriodLinesObject";
                str.equals(str2);
                i10 = 0;
                break;
            case 633426526:
                str2 = "CThreeWavesObject";
                str.equals(str2);
                i10 = 0;
                break;
            case 826758298:
                if (!str.equals("CRayLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 9;
                }
                break;
            case 827023504:
                if (!str.equals("CStraightLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 8;
                }
                break;
            case 916029520:
                if (!str.equals("CBandSegLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 19;
                }
                break;
            case 942058010:
                str2 = "CMagnifierObject";
                str.equals(str2);
                i10 = 0;
                break;
            case 1037884066:
                if (!str.equals("CVertiStraightLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 4;
                }
                break;
            case 1095856039:
                if (!str.equals("CHoriSegLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 1;
                }
                break;
            case 1197575818:
                str2 = "CTriangleObject";
                str.equals(str2);
                i10 = 0;
                break;
            case 1759461627:
                if (!str.equals("CFibFansObject")) {
                    i10 = 0;
                } else {
                    i10 = 15;
                }
                break;
            case 2071238210:
                if (!str.equals("CTriParallelLineObject")) {
                    i10 = 0;
                } else {
                    i10 = 11;
                }
                break;
            default:
                i10 = 0;
                break;
        }
        kLineManagerA.v0(16, i10);
    }
}
