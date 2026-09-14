package sp.aicoin_kline.chart;

import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import Rj.C2746s;
import Rj.C2757v1;
import Rj.C2765z;
import Rj.G;
import Rj.I;
import Rj.L0;
import Rj.RunnableC2726l;
import Rj.RunnableC2729m;
import Rj.U;
import Rj.X;
import Rj.r;
import Rj.y1;
import Sf.N;
import Sf.z;
import Yj.a;
import android.content.Context;
import android.graphics.Canvas;
import android.os.Handler;
import android.os.Looper;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;
import com.umeng.analytics.pro.am;
import com.umeng.analytics.pro.d;
import fk.C7389n;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kotlin.Metadata;
import kotlin.jvm.functions.Function1;
import nk.n;
import nk.q;
import org.apache.tika.metadata.OfficeOpenXMLExtended;
import org.apache.tika.mime.MimeTypesReaderMetKeys;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.AISRLData;
import sp.aicoin_kline.chart.data.EstimatedLiqVpcTimePoints;
import sp.aicoin_kline.chart.data.drawing.DrawingItem;
import sp.aicoin_kline.chart.viewmodel.OutSideIndicData;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
@Metadata(d1 = {"\u0000À\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0002\b\f\n\u0002\u0010\t\n\u0002\b\u0003\n\u0002\u0010\u000b\n\u0002\b\t\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010%\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0010 \n\u0002\u0010\u0006\n\u0002\b\u0002\n\u0002\u0010!\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010$\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0010\b\n\u0002\b\t\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0010\u0007\n\u0002\b\f\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0002\b\t\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0012\b\u0007\u0018\u00002\u00020\u0001B\u0019\b\u0016\u0012\u0006\u0010\u0003\u001a\u00020\u0002\u0012\u0006\u0010\u0005\u001a\u00020\u0004¢\u0006\u0004\b\u0006\u0010\u0007J\u0011\u0010\t\u001a\u0004\u0018\u00010\bH\u0002¢\u0006\u0004\b\t\u0010\nJ\u000f\u0010\f\u001a\u00020\u000bH\u0016¢\u0006\u0004\b\f\u0010\rJ\r\u0010\u000e\u001a\u00020\u000b¢\u0006\u0004\b\u000e\u0010\rJ\u0015\u0010\u0011\u001a\u00020\u000b2\u0006\u0010\u0010\u001a\u00020\u000f¢\u0006\u0004\b\u0011\u0010\u0012J\r\u0010\u0013\u001a\u00020\u000b¢\u0006\u0004\b\u0013\u0010\rJ\r\u0010\u0014\u001a\u00020\u000b¢\u0006\u0004\b\u0014\u0010\rJ\r\u0010\u0015\u001a\u00020\u000b¢\u0006\u0004\b\u0015\u0010\rJ\r\u0010\u0016\u001a\u00020\u000b¢\u0006\u0004\b\u0016\u0010\rJ\r\u0010\u0017\u001a\u00020\u000b¢\u0006\u0004\b\u0017\u0010\rJ\r\u0010\u0018\u001a\u00020\u000b¢\u0006\u0004\b\u0018\u0010\rJ\r\u0010\u0019\u001a\u00020\u000b¢\u0006\u0004\b\u0019\u0010\rJ\r\u0010\u001a\u001a\u00020\u000b¢\u0006\u0004\b\u001a\u0010\rJ\r\u0010\u001b\u001a\u00020\u000b¢\u0006\u0004\b\u001b\u0010\rJ\u0015\u0010\u001e\u001a\u00020\u000b2\u0006\u0010\u001d\u001a\u00020\u001c¢\u0006\u0004\b\u001e\u0010\u001fJ\r\u0010!\u001a\u00020 ¢\u0006\u0004\b!\u0010\"J\r\u0010#\u001a\u00020 ¢\u0006\u0004\b#\u0010\"J\u0017\u0010%\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020 H\u0000¢\u0006\u0004\b%\u0010&J\r\u0010'\u001a\u00020\u000b¢\u0006\u0004\b'\u0010\rJ\u0015\u0010)\u001a\u00020\u000b2\u0006\u0010(\u001a\u00020 ¢\u0006\u0004\b)\u0010&J\u0017\u0010,\u001a\u00020 2\u0006\u0010+\u001a\u00020*H\u0016¢\u0006\u0004\b,\u0010-J\u000f\u0010.\u001a\u00020\u000bH\u0016¢\u0006\u0004\b.\u0010\rJ\r\u0010/\u001a\u00020\u000b¢\u0006\u0004\b/\u0010\rJ\u0017\u00102\u001a\u00020\u000b2\u0006\u00101\u001a\u000200H\u0014¢\u0006\u0004\b2\u00103J\u000f\u00104\u001a\u00020\u000bH\u0014¢\u0006\u0004\b4\u0010\rJ\u0015\u00107\u001a\u00020\u000b2\u0006\u00106\u001a\u000205¢\u0006\u0004\b7\u00108J\r\u00109\u001a\u000205¢\u0006\u0004\b9\u0010:J\u0017\u0010=\u001a\u00020\u000b2\b\u0010<\u001a\u0004\u0018\u00010;¢\u0006\u0004\b=\u0010>J5\u0010A\u001a\u00020\u000b2&\u0010<\u001a\"\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020;\u0018\u00010?j\u0010\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020;\u0018\u0001`@¢\u0006\u0004\bA\u0010BJ\u001b\u0010E\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020D0C¢\u0006\u0004\bE\u0010FJ5\u0010K\u001a\u00020\u000b2\u0012\u0010<\u001a\u000e\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020H0G2\b\b\u0002\u0010I\u001a\u00020 2\b\b\u0002\u0010J\u001a\u00020 ¢\u0006\u0004\bK\u0010LJ'\u0010O\u001a\u00020\u000b2\u0018\u0010<\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020N0G0M¢\u0006\u0004\bO\u0010PJ%\u0010S\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020R0Q2\b\b\u0002\u0010I\u001a\u00020 ¢\u0006\u0004\bS\u0010TJ%\u0010W\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020U0Q2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\bW\u0010TJ#\u0010Z\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020U0Q2\u0006\u0010Y\u001a\u00020X¢\u0006\u0004\bZ\u0010[J\u001f\u0010]\u001a\u00020\u000b2\u0006\u0010<\u001a\u00020\\2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\b]\u0010^J%\u0010`\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020_0Q2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\b`\u0010TJ\u0017\u0010c\u001a\u00020\u000b2\b\u0010b\u001a\u0004\u0018\u00010a¢\u0006\u0004\bc\u0010dJ%\u0010f\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020e0Q2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\bf\u0010TJ%\u0010h\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020g0Q2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\bh\u0010TJ%\u0010j\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020i0M2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\bj\u0010TJ\u001b\u0010m\u001a\u00020\u000b2\f\u0010l\u001a\b\u0012\u0004\u0012\u00020k0M¢\u0006\u0004\bm\u0010PJ%\u0010o\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020n0M2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\bo\u0010TJ%\u0010r\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020p0M2\b\b\u0002\u0010q\u001a\u00020 ¢\u0006\u0004\br\u0010TJ%\u0010s\u001a\u00020\u000b2\f\u0010<\u001a\b\u0012\u0004\u0012\u00020p0M2\b\b\u0002\u0010q\u001a\u00020 ¢\u0006\u0004\bs\u0010TJ5\u0010v\u001a\u00020\u000b2\u0012\u0010<\u001a\u000e\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020p0t2\b\b\u0002\u0010q\u001a\u00020 2\b\b\u0002\u0010u\u001a\u00020 ¢\u0006\u0004\bv\u0010LJ\u001d\u0010y\u001a\u00020\u000b2\u0006\u0010w\u001a\u00020 2\u0006\u0010x\u001a\u00020 ¢\u0006\u0004\by\u0010zJ1\u0010|\u001a\u00020\u000b2\u0018\u0010<\u001a\u0014\u0012\u0004\u0012\u00020\u000f\u0012\n\u0012\b\u0012\u0004\u0012\u00020{0M0t2\b\b\u0002\u0010V\u001a\u00020 ¢\u0006\u0004\b|\u0010}J\u0016\u0010\u007f\u001a\u00020\u000b2\u0006\u0010~\u001a\u00020N¢\u0006\u0005\b\u007f\u0010\u0080\u0001J\u000f\u0010\u0081\u0001\u001a\u00020\u000b¢\u0006\u0005\b\u0081\u0001\u0010\rJ.\u0010\u0086\u0001\u001a\u00030\u0082\u00012\b\u0010\u0083\u0001\u001a\u00030\u0082\u00012\b\u0010\u0084\u0001\u001a\u00030\u0082\u00012\u0007\u0010\u0085\u0001\u001a\u00020 ¢\u0006\u0006\b\u0086\u0001\u0010\u0087\u0001J%\u0010\u0089\u0001\u001a\u00030\u0082\u00012\b\u0010\u0088\u0001\u001a\u00030\u0082\u00012\b\u0010\u0084\u0001\u001a\u00030\u0082\u0001¢\u0006\u0006\b\u0089\u0001\u0010\u008a\u0001J\u0011\u0010\u008b\u0001\u001a\u00020\u000bH\u0007¢\u0006\u0005\b\u008b\u0001\u0010\rJ\u001c\u0010\u008e\u0001\u001a\u00020\u000b2\n\u0010\u008d\u0001\u001a\u0005\u0018\u00010\u008c\u0001¢\u0006\u0006\b\u008e\u0001\u0010\u008f\u0001J\u000f\u0010\u0090\u0001\u001a\u00020\u000b¢\u0006\u0005\b\u0090\u0001\u0010\rJ\u0012\u0010\u0091\u0001\u001a\u0004\u0018\u00010D¢\u0006\u0006\b\u0091\u0001\u0010\u0092\u0001J\u0013\u0010\u0094\u0001\u001a\u0005\u0018\u00010\u0093\u0001¢\u0006\u0006\b\u0094\u0001\u0010\u0095\u0001J\u001a\u0010\u0097\u0001\u001a\u00020\u000b2\b\u0010\u0096\u0001\u001a\u00030\u0082\u0001¢\u0006\u0006\b\u0097\u0001\u0010\u0098\u0001J\u001f\u0010\u009b\u0001\u001a\u00020\u000b2\u000e\u0010\u009a\u0001\u001a\t\u0012\u0005\u0012\u00030\u0099\u00010Q¢\u0006\u0005\b\u009b\u0001\u0010PJ\u001a\u0010\u009d\u0001\u001a\u00020\u000b2\b\u0010\u009c\u0001\u001a\u00030\u0099\u0001¢\u0006\u0006\b\u009d\u0001\u0010\u009e\u0001J\u000f\u0010\u009f\u0001\u001a\u00020\u000b¢\u0006\u0005\b\u009f\u0001\u0010\rJ\u000f\u0010 \u0001\u001a\u00020\u000b¢\u0006\u0005\b \u0001\u0010\rJ\u000f\u0010¡\u0001\u001a\u00020\u000b¢\u0006\u0005\b¡\u0001\u0010\rJ#\u0010¤\u0001\u001a\u00020\u000b2\u0007\u0010¢\u0001\u001a\u00020 2\b\u0010£\u0001\u001a\u00030\u0082\u0001¢\u0006\u0006\b¤\u0001\u0010¥\u0001R\u001c\u0010ª\u0001\u001a\u00030¦\u00018\u0006¢\u0006\u000f\n\u0005\b\u001a\u0010§\u0001\u001a\u0006\b¨\u0001\u0010©\u0001R1\u0010±\u0001\u001a\u000b\u0012\u0004\u0012\u00020\u000b\u0018\u00010«\u00018\u0006@\u0006X\u0086\u000e¢\u0006\u0017\n\u0005\b\u0018\u0010¬\u0001\u001a\u0006\b\u00ad\u0001\u0010®\u0001\"\u0006\b¯\u0001\u0010°\u0001R'\u0010´\u0001\u001a\u00020 2\u0007\u0010²\u0001\u001a\u00020 8\u0006@BX\u0086\u000e¢\u0006\r\n\u0004\b\u0019\u0010r\u001a\u0005\b³\u0001\u0010\"R8\u0010»\u0001\u001a\u0011\u0012\u0004\u0012\u00020 \u0012\u0004\u0012\u00020\u000b\u0018\u00010µ\u00018\u0006@\u0006X\u0086\u000e¢\u0006\u0018\n\u0006\b\u0081\u0001\u0010¶\u0001\u001a\u0006\b·\u0001\u0010¸\u0001\"\u0006\b¹\u0001\u0010º\u0001R\u001a\u0010¿\u0001\u001a\u0005\u0018\u00010¼\u00018BX\u0082\u0004¢\u0006\b\u001a\u0006\b½\u0001\u0010¾\u0001R\u001a\u0010Ã\u0001\u001a\u0005\u0018\u00010À\u00018BX\u0082\u0004¢\u0006\b\u001a\u0006\bÁ\u0001\u0010Â\u0001R\u0014\u0010Æ\u0001\u001a\u00020\u001c8F¢\u0006\b\u001a\u0006\bÄ\u0001\u0010Å\u0001R\u0014\u0010È\u0001\u001a\u00020\u001c8F¢\u0006\b\u001a\u0006\bÇ\u0001\u0010Å\u0001R\u0015\u0010Ë\u0001\u001a\u00030\u0082\u00018F¢\u0006\b\u001a\u0006\bÉ\u0001\u0010Ê\u0001R\u0015\u0010Í\u0001\u001a\u00030\u0082\u00018F¢\u0006\b\u001a\u0006\bÌ\u0001\u0010Ê\u0001R-\u0010Î\u0001\u001a\u0004\u0018\u00010\u000f2\t\u0010Î\u0001\u001a\u0004\u0018\u00010\u000f8F@FX\u0086\u000e¢\u0006\u000f\u001a\u0006\bÏ\u0001\u0010Ð\u0001\"\u0005\bÑ\u0001\u0010\u0012¨\u0006Ò\u0001"}, d2 = {"Lsp/aicoin_kline/chart/Chart;", "Landroid/view/View;", "Landroid/content/Context;", d.f89950R, "Landroid/util/AttributeSet;", "attrs", "<init>", "(Landroid/content/Context;Landroid/util/AttributeSet;)V", "LRj/G;", "getMainDrawer", "()LRj/G;", "LQf/H;", "invalidate", "()V", am.aH, "", "template", "setCurrentDataSource", "(Ljava/lang/String;)V", am.aG, "j", "f", "o", "k", "l", "m", "g", "y", "", "timestamp", "B", "(J)V", "", "C", "()Z", am.aD, "isScaled", "F", "(Z)V", am.aC, "enable", "r", "Landroid/view/MotionEvent;", "event", "onTouchEvent", "(Landroid/view/MotionEvent;)Z", "computeScroll", "D", "Landroid/graphics/Canvas;", "canvas", "onDraw", "(Landroid/graphics/Canvas;)V", "onDetachedFromWindow", "Lak/d;", "klineFlavor", "Q", "(Lak/d;)V", "getKlineFlavor", "()Lak/d;", "Llk/a;", "data", "H", "(Llk/a;)V", "Ljava/util/LinkedHashMap;", "Lkotlin/collections/LinkedHashMap;", "G", "(Ljava/util/LinkedHashMap;)V", "", "Lsp/aicoin_kline/chart/data/drawing/DrawingItem;", "I", "([Lsp/aicoin_kline/chart/data/drawing/DrawingItem;)V", "", "LSj/g;", "loadEarlier", "refreshData", "P", "(Ljava/util/Map;ZZ)V", "", "", "j0", "(Ljava/util/List;)V", "", "LSj/h;", "Y", "(Ljava/util/List;Z)V", "Lsp/aicoin_kline/chart/data/LargeOrderItem;", "resetData", "S", "LRj/X;", "updateMode", "R", "(Ljava/util/List;LRj/X;)V", "Lsp/aicoin_kline/chart/data/AISRLData;", "J", "(Lsp/aicoin_kline/chart/data/AISRLData;Z)V", "Lsp/aicoin_kline/chart/data/LiQuiLineItem;", "W", "Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePoints;", "timePoints", "M", "(Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePoints;)V", "Lsp/aicoin_kline/chart/data/AIHandleLineItem;", "N", "Lsp/aicoin_kline/chart/data/AlertLineItem;", "K", "Lsp/aicoin_kline/chart/data/AIWinRateItem;", "k0", "LSj/k;", "items", "l0", "Lsp/aicoin_kline/chart/data/LargeTradeItem;", "U", "Lsp/aicoin_kline/chart/data/ScriptDrawData;", "isSocket", "Z", "a0", "", "isChangePeriod", "h0", "isHide", "isResume", "E", "(ZZ)V", "LSj/f;", "f0", "(Ljava/util/Map;Z)V", "price", "g0", "(D)V", "n", "", "baseHeight", "indicatorCount", "lowerThanBaseHeightAllowed", "t", "(IIZ)I", "totalHeight", am.aB, "(II)I", "x", "LRj/U;", "adapter", "setInfoWindowAdapter", "(LRj/U;)V", "A", "getSelectedDrawingItem", "()Lsp/aicoin_kline/chart/data/drawing/DrawingItem;", "Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;", "getSelectedDrawingItemOptions", "()Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;", "lineColor", "c0", "(I)V", "", "lineDash", "d0", "lineWidth", "e0", "(F)V", OfficeOpenXMLExtended.WORD_PROCESSING_PREFIX, "q", am.ax, "showBackground", "bgColor", "b0", "(ZI)V", "LRj/r;", "LRj/r;", "getSettings", "()LRj/r;", "settings", "Lkotlin/Function0;", "Lgg/a;", "getOnMagnifierStateChanged", "()Lgg/a;", "setOnMagnifierStateChanged", "(Lgg/a;)V", "onMagnifierStateChanged", MimeTypesReaderMetKeys.MATCH_VALUE_ATTR, "v", "isMainYAxisScaled", "Lkotlin/Function1;", "Lkotlin/jvm/functions/Function1;", "getOnMainYAxisScaleStateChanged", "()Lkotlin/jvm/functions/Function1;", "setOnMainYAxisScaleStateChanged", "(Lkotlin/jvm/functions/Function1;)V", "onMainYAxisScaleStateChanged", "LRj/z;", "getDs", "()LRj/z;", "ds", "LRj/q;", "getMgr", "()LRj/q;", "mgr", "getLastDate", "()J", "lastDate", "getFirstDate", "firstDate", "getDataCount", "()I", "dataCount", "getDataRealCount", "dataRealCount", "title", "getTitle", "()Ljava/lang/String;", "setTitle", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final class Chart extends View {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f142406a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public a f142407b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public C2732n f142408c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final KLineManager f142409d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public Wj.a f142410e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public C2746s f142411f;

    /* JADX INFO: renamed from: g, reason: collision with root package name and from kotlin metadata */
    public final r settings;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final I f142413h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final Handler f142414i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public boolean f142415j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final Runnable f142416k;

    /* JADX INFO: renamed from: l, reason: collision with root package name and from kotlin metadata */
    public p146gg.a onMagnifierStateChanged;

    /* JADX INFO: renamed from: m, reason: collision with root package name and from kotlin metadata */
    public boolean isMainYAxisScaled;

    /* JADX INFO: renamed from: n, reason: collision with root package name and from kotlin metadata */
    public Function1 onMainYAxisScaleStateChanged;

    public Chart(Context context, AttributeSet attributeSet) {
        super(context, attributeSet);
        this.f142406a = "ds0";
        this.f142409d = KLineManager.f142490O.a();
        this.settings = new r();
        this.f142413h = new I();
        this.f142414i = new Handler(Looper.getMainLooper());
        this.f142416k = new RunnableC2729m(this);
        a();
    }

    public static /* synthetic */ void L(Chart chart, List list, boolean z10, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            z10 = true;
        }
        chart.K(list, z10);
    }

    public static /* synthetic */ void O(Chart chart, List list, boolean z10, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            z10 = true;
        }
        chart.N(list, z10);
    }

    public static /* synthetic */ void T(Chart chart, List list, boolean z10, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            z10 = true;
        }
        chart.S(list, z10);
    }

    public static /* synthetic */ void V(Chart chart, List list, boolean z10, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            z10 = true;
        }
        chart.U(list, z10);
    }

    public static /* synthetic */ void X(Chart chart, List list, boolean z10, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            z10 = true;
        }
        chart.W(list, z10);
    }

    public static final void b(Chart chart) {
        chart.f142415j = false;
        super.invalidate();
    }

    public static final void c(Chart chart, List list, X x10) {
        chart.R(list, x10);
    }

    private final C2765z getDs() {
        C2732n c2732n = this.f142408c;
        if (c2732n != null) {
            return c2732n.d();
        }
        return null;
    }

    private final G getMainDrawer() {
        C2741q mgr = getMgr();
        if (mgr != null) {
            return mgr.i(this.f142406a);
        }
        return null;
    }

    private final C2741q getMgr() {
        C2732n c2732n = this.f142408c;
        if (c2732n != null) {
            return c2732n.b();
        }
        return null;
    }

    public static /* synthetic */ void i0(Chart chart, Map map, boolean z10, boolean z11, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            z10 = false;
        }
        if ((i10 & 4) != 0) {
            z11 = false;
        }
        chart.h0(map, z10, z11);
    }

    public final void A() {
        G mainDrawer = getMainDrawer();
        if (mainDrawer != null) {
            mainDrawer.G();
        }
        invalidate();
    }

    public final void B(long timestamp) {
        C2741q c2741qB;
        y1 y1VarM;
        C2732n c2732n = this.f142408c;
        if (c2732n != null && (c2741qB = c2732n.b()) != null && (y1VarM = c2741qB.m(this.f142406a)) != null) {
            y1VarM.S(timestamp);
        }
        invalidate();
    }

    /* JADX WARN: Code duplicated, block: B:11:0x001a  */
    public final boolean C() {
        boolean z10;
        C2741q c2741qB;
        y1 y1VarM;
        C2732n c2732n = this.f142408c;
        if (c2732n != null && (c2741qB = c2732n.b()) != null && (y1VarM = c2741qB.m(this.f142406a)) != null) {
            z10 = y1VarM.T();
        }
        if (z10) {
            u();
        }
        return z10;
    }

    public final void D() {
        Wj.a aVar = this.f142410e;
        if (aVar != null) {
            aVar.v();
        }
    }

    public final void E(boolean isHide, boolean isResume) {
        this.f142409d.b1(isHide);
        if (isResume) {
            invalidate();
        }
    }

    public final void F(boolean isScaled) {
        if (this.isMainYAxisScaled == isScaled) {
            return;
        }
        this.isMainYAxisScaled = isScaled;
        Function1 function1 = this.onMainYAxisScaleStateChanged;
        if (function1 != null) {
            function1.invoke(Boolean.valueOf(isScaled));
        }
    }

    public final void G(LinkedHashMap data) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.H(this.f142406a, data);
        }
        invalidate();
    }

    public final void H(lk.a data) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.y(this.f142406a, data);
        }
        invalidate();
    }

    public final void I(DrawingItem[] data) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.z(this.f142406a, data);
        }
        invalidate();
    }

    public final void J(AISRLData data, boolean resetData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.w(this.f142406a, data, Boolean.valueOf(resetData));
        }
        invalidate();
    }

    public final void K(List data, boolean resetData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.x(this.f142406a, data, Boolean.valueOf(resetData));
        }
        invalidate();
    }

    public final void M(EstimatedLiqVpcTimePoints timePoints) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.A(this.f142406a, timePoints);
        }
        invalidate();
    }

    public final void N(List data, boolean resetData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.C(this.f142406a, data, Boolean.valueOf(resetData));
        }
        invalidate();
    }

    public final void P(Map data, boolean loadEarlier, boolean refreshData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.D(this.f142406a, data, loadEarlier, refreshData);
        }
        invalidate();
    }

    public final void Q(ak.d klineFlavor) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.B(this.f142406a, klineFlavor);
        }
        invalidate();
    }

    public final void R(List data, X updateMode) {
        if (!AbstractC7609s.f(Looper.myLooper(), Looper.getMainLooper())) {
            this.f142414i.post(new RunnableC2726l(this, z.u1(data), updateMode));
        } else {
            C2741q mgr = getMgr();
            if (mgr != null) {
                mgr.E(this.f142406a, data, updateMode);
            }
            invalidate();
        }
    }

    public final void S(List data, boolean resetData) {
        R(data, resetData ? X.RESET_ALL : X.APPEND_OR_MERGE);
    }

    public final void U(List data, boolean resetData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.F(this.f142406a, data, Boolean.valueOf(resetData));
        }
        invalidate();
    }

    public final void W(List data, boolean resetData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.G(this.f142406a, data, Boolean.valueOf(resetData));
        }
        invalidate();
    }

    public final void Y(List data, boolean loadEarlier) {
        C2741q mgr;
        C2741q mgr2 = getMgr();
        if (mgr2 != null) {
            mgr2.I(this.f142406a, data, loadEarlier);
        }
        if (data.size() > 1 && (mgr = getMgr()) != null) {
            mgr.f19507o = data;
        }
        invalidate();
    }

    public final void Z(List data, boolean isSocket) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.J(this.f142406a, data, Boolean.valueOf(isSocket));
        }
        if (isSocket) {
            return;
        }
        invalidate();
    }

    public final void a() {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.v();
        }
        C2732n c2732n = new C2732n(getContext());
        c2732n.f(this);
        KLineManager.f142490O.a().l0(this);
        this.f142408c = c2732n;
        Wj.a aVar = new Wj.a(c2732n, this, this.f142406a);
        this.f142411f = new C2746s(c2732n, this, aVar, this.f142406a);
        this.f142407b = (a) Yj.d.a("animation");
        this.f142410e = aVar;
        new OutSideIndicData(0.0d, 0.0d, 0.0f, 0.0f, 0L, 0L, 0, 0, 0.0f, 511, null);
    }

    public final void a0(List data, boolean isSocket) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.K(this.f142406a, data, Boolean.valueOf(isSocket));
        }
        if (isSocket) {
            return;
        }
        invalidate();
    }

    public final void b0(boolean showBackground, int bgColor) {
        G mainDrawer = getMainDrawer();
        if (mainDrawer == null) {
            return;
        }
        mainDrawer.J(showBackground, bgColor);
        invalidate();
    }

    public final void c0(int lineColor) {
        G mainDrawer = getMainDrawer();
        if (mainDrawer == null) {
            return;
        }
        mainDrawer.K(lineColor);
        invalidate();
    }

    @Override // android.view.View
    public void computeScroll() {
        C2746s c2746s = this.f142411f;
        if (c2746s != null) {
            c2746s.a();
        }
    }

    public final boolean d(boolean z10, boolean z11) {
        if (z11) {
            Wj.a aVar = this.f142410e;
            if (AbstractC7609s.f(aVar != null ? Boolean.valueOf(aVar.u(z10)) : null, Boolean.TRUE)) {
                return true;
            }
        }
        C2741q mgr = getMgr();
        if (mgr != null) {
            AbstractC2759w0 abstractC2759w0L = mgr.l(this.f142406a + ".main");
            if (abstractC2759w0L == null || !abstractC2759w0L.F()) {
                return false;
            }
            if (z10) {
                u();
            }
            return true;
        }
        return false;
    }

    public final void d0(List lineDash) {
        G mainDrawer = getMainDrawer();
        if (mainDrawer == null) {
            return;
        }
        mainDrawer.L(lineDash);
        invalidate();
    }

    /* JADX WARN: Code duplicated, block: B:7:0x002a  */
    public final void e(boolean z10, boolean z11) {
        Double dValueOf;
        I i10 = this.f142413h;
        C2741q mgr = getMgr();
        if (mgr != null) {
            AbstractC2759w0 abstractC2759w0L = mgr.l(this.f142406a + ".main");
            if (abstractC2759w0L != null) {
                dValueOf = Double.valueOf(abstractC2759w0L.B());
            } else {
                dValueOf = null;
            }
        } else {
            dValueOf = null;
        }
        if (i10.b(z10, this.isMainYAxisScaled || !(dValueOf == null || AbstractC7609s.c(dValueOf, 1.0d))) && d(z11, z11)) {
            this.f142413h.a();
        }
    }

    public final void e0(float lineWidth) {
        G mainDrawer = getMainDrawer();
        if (mainDrawer == null) {
            return;
        }
        mainDrawer.M(lineWidth);
        invalidate();
    }

    public final void f() {
        M(null);
    }

    public final void f0(Map data, boolean resetData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.L(this.f142406a, data, Boolean.valueOf(resetData));
        }
        C2741q mgr2 = getMgr();
        if (mgr2 != null) {
            mgr2.f19506n = data;
        }
        invalidate();
    }

    public final void g() {
        J(new AISRLData(null, null, null, 7, null), true);
    }

    public final void g0(double price) {
        C2765z ds = getDs();
        if (ds != null) {
            ds.w0(price);
        }
    }

    public final int getDataCount() {
        C2765z ds = getDs();
        if (ds != null) {
            return ds.B();
        }
        return 0;
    }

    public final int getDataRealCount() {
        C2765z ds = getDs();
        if (ds != null) {
            return ds.D();
        }
        return 0;
    }

    public final long getFirstDate() {
        C2765z ds = getDs();
        if (ds != null) {
            return ds.G();
        }
        return 0L;
    }

    public final ak.d getKlineFlavor() {
        ak.d dVarJ;
        C2741q mgr = getMgr();
        return (mgr == null || (dVarJ = mgr.j(this.f142406a)) == null) ? ak.d.NORMAL : dVarJ;
    }

    public final long getLastDate() {
        C2765z ds = getDs();
        if (ds != null) {
            return ds.N();
        }
        return 0L;
    }

    public final p146gg.a getOnMagnifierStateChanged() {
        return this.onMagnifierStateChanged;
    }

    public final Function1 getOnMainYAxisScaleStateChanged() {
        return this.onMainYAxisScaleStateChanged;
    }

    public final DrawingItem getSelectedDrawingItem() {
        G mainDrawer = getMainDrawer();
        if (mainDrawer != null) {
            return mainDrawer.w();
        }
        return null;
    }

    public final DrawingItem.Options getSelectedDrawingItemOptions() {
        G mainDrawer = getMainDrawer();
        if (mainDrawer != null) {
            return mainDrawer.x();
        }
        return null;
    }

    public final r getSettings() {
        return this.settings;
    }

    public final String getTitle() {
        C2741q mgr = getMgr();
        if (mgr != null) {
            return mgr.o();
        }
        return null;
    }

    public final void h() {
        C2741q c2741qB;
        y1 y1VarM;
        C2741q mgr = getMgr();
        if (mgr != null) {
            AbstractC2759w0 abstractC2759w0L = mgr.l(this.f142406a + ".main");
            if (abstractC2759w0L != null) {
                abstractC2759w0L.F();
            }
        }
        F(false);
        C2765z ds = getDs();
        if (ds != null) {
            ds.s();
            ds.u();
            ds.v();
            ds.y();
        }
        C2732n c2732n = this.f142408c;
        if (c2732n == null || (c2741qB = c2732n.b()) == null || (y1VarM = c2741qB.m(this.f142406a)) == null) {
            return;
        }
        y1VarM.V(true);
    }

    public final void h0(Map data, boolean isSocket, boolean isChangePeriod) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.M(this.f142406a, data, Boolean.valueOf(isSocket), Boolean.valueOf(isChangePeriod));
        }
        if (isSocket) {
            return;
        }
        invalidate();
    }

    public final void i() {
        C2765z ds = getDs();
        if (ds != null) {
            ds.t();
        }
    }

    @Override // android.view.View
    public void invalidate() {
        if (this.f142415j) {
            return;
        }
        this.f142415j = true;
        this.f142414i.post(this.f142416k);
    }

    public final void j() {
        T(this, new ArrayList(), false, 2, null);
    }

    public final void j0(List data) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.N(this.f142406a, data);
        }
        invalidate();
    }

    public final void k() {
        V(this, new ArrayList(), false, 2, null);
    }

    public final void k0(List data, boolean resetData) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.O(this.f142406a, data, Boolean.valueOf(resetData));
        }
        C2741q mgr2 = getMgr();
        if (mgr2 != null) {
            mgr2.f19505m = data;
        }
        invalidate();
    }

    public final void l() {
        C2765z ds = getDs();
        if (ds != null) {
            ds.w();
        }
    }

    public final void l0(List items) {
        C2765z ds = getDs();
        if (ds != null) {
            ds.f0(items);
        }
        invalidate();
    }

    public final void m() {
        C2765z ds = getDs();
        if (ds != null) {
            ds.x();
        }
    }

    public final void n() {
        C2765z ds = getDs();
        if (ds != null) {
            ds.d0(-1.0d);
        }
    }

    public final void o() {
        i0(this, N.j(), false, true, 2, null);
    }

    @Override // android.view.View
    public void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        KLineManager.a aVar = KLineManager.f142490O;
        if (aVar.a().g() == this) {
            aVar.a().l0(null);
        }
        this.f142415j = false;
        this.f142414i.removeCallbacks(this.f142416k);
        q.f134234e.b();
    }

    @Override // android.view.View
    public void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        C2741q mgr = getMgr();
        if (mgr != null && mgr.f19509q) {
            e(n.f(13), false);
            mgr.q(this.f142406a, 0, 0, getWidth(), getHeight());
            mgr.d(this.f142406a, canvas);
        }
    }

    @Override // android.view.View
    public boolean onTouchEvent(MotionEvent event) {
        C2765z ds;
        C2746s c2746s = this.f142411f;
        if (c2746s == null || (ds = getDs()) == null || ds.C().size() == 0) {
            return true;
        }
        boolean zF = n.f(13);
        e(zF, true);
        if (C7389n.f95436a.a(event)) {
            return true;
        }
        Wj.a aVar = this.f142410e;
        if (aVar != null) {
            aVar.t(event, zF);
        }
        c2746s.c(event);
        int action = event.getAction() & 255;
        if (action == 0) {
            c2746s.d(event);
        } else if (action == 1 || action == 6) {
            c2746s.e(event);
        }
        return true;
    }

    public final void p() {
        G mainDrawer = getMainDrawer();
        if (mainDrawer == null) {
            return;
        }
        mainDrawer.n();
        invalidate();
    }

    public final void q() {
        G mainDrawer = getMainDrawer();
        if (mainDrawer == null) {
            return;
        }
        mainDrawer.o();
        invalidate();
    }

    public final void r(boolean enable) {
        this.settings.d(enable);
    }

    public final int s(int totalHeight, int indicatorCount) {
        C2741q mgr = getMgr();
        if (mgr == null) {
            return 0;
        }
        C2702d c2702dE = mgr.e(this.f142406a + ".charts");
        L0 l10 = c2702dE instanceof L0 ? (L0) c2702dE : null;
        if (l10 == null) {
            return 0;
        }
        return l10.M(totalHeight, indicatorCount);
    }

    public final void setCurrentDataSource(String template) {
        String str = this.f142406a;
        if (str == null) {
            str = "";
        }
        C2746s c2746s = this.f142411f;
        if (c2746s != null) {
            c2746s.b();
        }
        C2732n c2732n = this.f142408c;
        if (c2732n != null) {
            C2757v1.f19568a.V(c2732n, template, str, "ai_chart");
        }
        F(false);
        this.f142409d.X0(template);
        invalidate();
    }

    public final void setInfoWindowAdapter(U adapter) {
        if (adapter != null) {
            adapter.L(this.f142406a);
            adapter.C(this.f142408c);
            C2741q mgr = getMgr();
            if (mgr != null) {
                mgr.s(this.f142406a, adapter);
            }
        }
    }

    public final void setOnMagnifierStateChanged(p146gg.a aVar) {
        this.onMagnifierStateChanged = aVar;
    }

    public final void setOnMainYAxisScaleStateChanged(Function1 function1) {
        this.onMainYAxisScaleStateChanged = function1;
    }

    public final void setTitle(String str) {
        C2741q mgr = getMgr();
        if (mgr != null) {
            mgr.u(str);
        }
    }

    public final int t(int baseHeight, int indicatorCount, boolean lowerThanBaseHeightAllowed) {
        C2741q mgr = getMgr();
        if (mgr == null) {
            return 0;
        }
        C2702d c2702dE = mgr.e(this.f142406a + ".charts");
        L0 l10 = c2702dE instanceof L0 ? (L0) c2702dE : null;
        if (l10 == null) {
            return 0;
        }
        return l10.N(baseHeight, indicatorCount, lowerThanBaseHeightAllowed);
    }

    public final void u() {
        this.f142415j = false;
        this.f142414i.removeCallbacks(this.f142416k);
        super.invalidate();
    }

    /* JADX INFO: renamed from: v, reason: from getter */
    public final boolean getIsMainYAxisScaled() {
        return this.isMainYAxisScaled;
    }

    public final void w() {
        G mainDrawer = getMainDrawer();
        if (mainDrawer == null) {
            return;
        }
        mainDrawer.E();
        invalidate();
    }

    public final void x() {
        a aVar = this.f142407b;
        if (aVar == null) {
            u();
        } else if (aVar.b() != 8) {
            u();
        }
    }

    public final void y() {
        C2741q c2741qB;
        y1 y1VarM;
        C2732n c2732n = this.f142408c;
        if (c2732n != null && (c2741qB = c2732n.b()) != null && (y1VarM = c2741qB.m(this.f142406a)) != null) {
            y1VarM.P();
        }
        invalidate();
    }

    public final boolean z() {
        return d(true, true);
    }
}
