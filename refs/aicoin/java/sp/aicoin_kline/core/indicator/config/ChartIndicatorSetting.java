package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import com.tencent.wcdb.database.SQLiteDatabase;
import com.tencent.wcdb.database.SQLiteGlobal;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import okhttp3.internal.http2.Http2Connection;
import org.apache.tika.metadata.DublinCore;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000÷\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0003\b¯\u0001\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B³\u0005\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u000b\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\r\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u000f\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0011\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0013\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0015\u0012\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\u0017\u0012\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u0019\u0012\n\b\u0002\u0010\u001a\u001a\u0004\u0018\u00010\u001b\u0012\n\b\u0002\u0010\u001c\u001a\u0004\u0018\u00010\u001d\u0012\n\b\u0002\u0010\u001e\u001a\u0004\u0018\u00010\u001f\u0012\n\b\u0002\u0010 \u001a\u0004\u0018\u00010!\u0012\n\b\u0002\u0010\"\u001a\u0004\u0018\u00010#\u0012\n\b\u0002\u0010$\u001a\u0004\u0018\u00010%\u0012\n\b\u0002\u0010&\u001a\u0004\u0018\u00010'\u0012\n\b\u0002\u0010(\u001a\u0004\u0018\u00010)\u0012\n\b\u0002\u0010*\u001a\u0004\u0018\u00010+\u0012\n\b\u0002\u0010,\u001a\u0004\u0018\u00010-\u0012\n\b\u0002\u0010.\u001a\u0004\u0018\u00010/\u0012\n\b\u0002\u00100\u001a\u0004\u0018\u000101\u0012\n\b\u0002\u00102\u001a\u0004\u0018\u000103\u0012\n\b\u0002\u00104\u001a\u0004\u0018\u000105\u0012\n\b\u0002\u00106\u001a\u0004\u0018\u000107\u0012\n\b\u0002\u00108\u001a\u0004\u0018\u000109\u0012\n\b\u0002\u0010:\u001a\u0004\u0018\u00010;\u0012\n\b\u0002\u0010<\u001a\u0004\u0018\u00010=\u0012\n\b\u0002\u0010>\u001a\u0004\u0018\u00010?\u0012\n\b\u0002\u0010@\u001a\u0004\u0018\u00010A\u0012\n\b\u0002\u0010B\u001a\u0004\u0018\u00010C\u0012\n\b\u0002\u0010D\u001a\u0004\u0018\u00010E\u0012\n\b\u0002\u0010F\u001a\u0004\u0018\u00010G\u0012\n\b\u0002\u0010H\u001a\u0004\u0018\u00010I\u0012\n\b\u0002\u0010J\u001a\u0004\u0018\u00010K\u0012\n\b\u0002\u0010L\u001a\u0004\u0018\u00010M\u0012\n\b\u0002\u0010N\u001a\u0004\u0018\u00010O\u0012\n\b\u0002\u0010P\u001a\u0004\u0018\u00010Q\u0012\n\b\u0002\u0010R\u001a\u0004\u0018\u00010S\u0012\n\b\u0002\u0010T\u001a\u0004\u0018\u00010U\u0012\n\b\u0002\u0010V\u001a\u0004\u0018\u00010W\u0012\n\b\u0002\u0010X\u001a\u0004\u0018\u00010Y\u0012\n\b\u0002\u0010Z\u001a\u0004\u0018\u00010[\u0012\n\b\u0002\u0010\\\u001a\u0004\u0018\u00010]\u0012\n\b\u0002\u0010^\u001a\u0004\u0018\u00010_\u0012\n\b\u0002\u0010`\u001a\u0004\u0018\u00010a\u0012\n\b\u0002\u0010b\u001a\u0004\u0018\u00010c\u0012\n\b\u0002\u0010d\u001a\u0004\u0018\u00010e\u0012\n\b\u0002\u0010f\u001a\u0004\u0018\u00010g\u0012\n\b\u0002\u0010h\u001a\u0004\u0018\u00010i\u0012\n\b\u0002\u0010j\u001a\u0004\u0018\u00010k\u0012\n\b\u0002\u0010l\u001a\u0004\u0018\u00010m\u0012\n\b\u0002\u0010n\u001a\u0004\u0018\u00010o\u0012\n\b\u0002\u0010p\u001a\u0004\u0018\u00010q\u0012\n\b\u0002\u0010r\u001a\u0004\u0018\u00010s¢\u0006\u0004\bt\u0010uJ\f\u0010è\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010é\u0001\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\f\u0010ê\u0001\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\f\u0010ë\u0001\u001a\u0004\u0018\u00010\tHÆ\u0003J\f\u0010ì\u0001\u001a\u0004\u0018\u00010\u000bHÆ\u0003J\f\u0010í\u0001\u001a\u0004\u0018\u00010\rHÆ\u0003J\f\u0010î\u0001\u001a\u0004\u0018\u00010\u000fHÆ\u0003J\f\u0010ï\u0001\u001a\u0004\u0018\u00010\u0011HÆ\u0003J\f\u0010ð\u0001\u001a\u0004\u0018\u00010\u0013HÆ\u0003J\f\u0010ñ\u0001\u001a\u0004\u0018\u00010\u0015HÆ\u0003J\f\u0010ò\u0001\u001a\u0004\u0018\u00010\u0017HÆ\u0003J\f\u0010ó\u0001\u001a\u0004\u0018\u00010\u0019HÆ\u0003J\f\u0010ô\u0001\u001a\u0004\u0018\u00010\u001bHÆ\u0003J\f\u0010õ\u0001\u001a\u0004\u0018\u00010\u001dHÆ\u0003J\f\u0010ö\u0001\u001a\u0004\u0018\u00010\u001fHÆ\u0003J\f\u0010÷\u0001\u001a\u0004\u0018\u00010!HÆ\u0003J\f\u0010ø\u0001\u001a\u0004\u0018\u00010#HÆ\u0003J\f\u0010ù\u0001\u001a\u0004\u0018\u00010%HÆ\u0003J\f\u0010ú\u0001\u001a\u0004\u0018\u00010'HÆ\u0003J\f\u0010û\u0001\u001a\u0004\u0018\u00010)HÆ\u0003J\f\u0010ü\u0001\u001a\u0004\u0018\u00010+HÆ\u0003J\f\u0010ý\u0001\u001a\u0004\u0018\u00010-HÆ\u0003J\f\u0010þ\u0001\u001a\u0004\u0018\u00010/HÆ\u0003J\f\u0010ÿ\u0001\u001a\u0004\u0018\u000101HÆ\u0003J\f\u0010\u0080\u0002\u001a\u0004\u0018\u000103HÆ\u0003J\f\u0010\u0081\u0002\u001a\u0004\u0018\u000105HÆ\u0003J\f\u0010\u0082\u0002\u001a\u0004\u0018\u000107HÆ\u0003J\f\u0010\u0083\u0002\u001a\u0004\u0018\u000109HÆ\u0003J\f\u0010\u0084\u0002\u001a\u0004\u0018\u00010;HÆ\u0003J\f\u0010\u0085\u0002\u001a\u0004\u0018\u00010=HÆ\u0003J\f\u0010\u0086\u0002\u001a\u0004\u0018\u00010?HÆ\u0003J\f\u0010\u0087\u0002\u001a\u0004\u0018\u00010AHÆ\u0003J\f\u0010\u0088\u0002\u001a\u0004\u0018\u00010CHÆ\u0003J\f\u0010\u0089\u0002\u001a\u0004\u0018\u00010EHÆ\u0003J\f\u0010\u008a\u0002\u001a\u0004\u0018\u00010GHÆ\u0003J\f\u0010\u008b\u0002\u001a\u0004\u0018\u00010IHÆ\u0003J\f\u0010\u008c\u0002\u001a\u0004\u0018\u00010KHÆ\u0003J\f\u0010\u008d\u0002\u001a\u0004\u0018\u00010MHÆ\u0003J\f\u0010\u008e\u0002\u001a\u0004\u0018\u00010OHÆ\u0003J\f\u0010\u008f\u0002\u001a\u0004\u0018\u00010QHÆ\u0003J\f\u0010\u0090\u0002\u001a\u0004\u0018\u00010SHÆ\u0003J\f\u0010\u0091\u0002\u001a\u0004\u0018\u00010UHÆ\u0003J\f\u0010\u0092\u0002\u001a\u0004\u0018\u00010WHÆ\u0003J\f\u0010\u0093\u0002\u001a\u0004\u0018\u00010YHÆ\u0003J\f\u0010\u0094\u0002\u001a\u0004\u0018\u00010[HÆ\u0003J\f\u0010\u0095\u0002\u001a\u0004\u0018\u00010]HÆ\u0003J\f\u0010\u0096\u0002\u001a\u0004\u0018\u00010_HÆ\u0003J\f\u0010\u0097\u0002\u001a\u0004\u0018\u00010aHÆ\u0003J\f\u0010\u0098\u0002\u001a\u0004\u0018\u00010cHÆ\u0003J\f\u0010\u0099\u0002\u001a\u0004\u0018\u00010eHÆ\u0003J\f\u0010\u009a\u0002\u001a\u0004\u0018\u00010gHÆ\u0003J\f\u0010\u009b\u0002\u001a\u0004\u0018\u00010iHÆ\u0003J\f\u0010\u009c\u0002\u001a\u0004\u0018\u00010kHÆ\u0003J\f\u0010\u009d\u0002\u001a\u0004\u0018\u00010mHÆ\u0003J\f\u0010\u009e\u0002\u001a\u0004\u0018\u00010oHÆ\u0003J\f\u0010\u009f\u0002\u001a\u0004\u0018\u00010qHÆ\u0003J\f\u0010 \u0002\u001a\u0004\u0018\u00010sHÆ\u0003J¶\u0005\u0010¡\u0002\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u000b2\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\r2\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u000f2\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00112\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00132\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00152\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\u00172\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u00192\n\b\u0002\u0010\u001a\u001a\u0004\u0018\u00010\u001b2\n\b\u0002\u0010\u001c\u001a\u0004\u0018\u00010\u001d2\n\b\u0002\u0010\u001e\u001a\u0004\u0018\u00010\u001f2\n\b\u0002\u0010 \u001a\u0004\u0018\u00010!2\n\b\u0002\u0010\"\u001a\u0004\u0018\u00010#2\n\b\u0002\u0010$\u001a\u0004\u0018\u00010%2\n\b\u0002\u0010&\u001a\u0004\u0018\u00010'2\n\b\u0002\u0010(\u001a\u0004\u0018\u00010)2\n\b\u0002\u0010*\u001a\u0004\u0018\u00010+2\n\b\u0002\u0010,\u001a\u0004\u0018\u00010-2\n\b\u0002\u0010.\u001a\u0004\u0018\u00010/2\n\b\u0002\u00100\u001a\u0004\u0018\u0001012\n\b\u0002\u00102\u001a\u0004\u0018\u0001032\n\b\u0002\u00104\u001a\u0004\u0018\u0001052\n\b\u0002\u00106\u001a\u0004\u0018\u0001072\n\b\u0002\u00108\u001a\u0004\u0018\u0001092\n\b\u0002\u0010:\u001a\u0004\u0018\u00010;2\n\b\u0002\u0010<\u001a\u0004\u0018\u00010=2\n\b\u0002\u0010>\u001a\u0004\u0018\u00010?2\n\b\u0002\u0010@\u001a\u0004\u0018\u00010A2\n\b\u0002\u0010B\u001a\u0004\u0018\u00010C2\n\b\u0002\u0010D\u001a\u0004\u0018\u00010E2\n\b\u0002\u0010F\u001a\u0004\u0018\u00010G2\n\b\u0002\u0010H\u001a\u0004\u0018\u00010I2\n\b\u0002\u0010J\u001a\u0004\u0018\u00010K2\n\b\u0002\u0010L\u001a\u0004\u0018\u00010M2\n\b\u0002\u0010N\u001a\u0004\u0018\u00010O2\n\b\u0002\u0010P\u001a\u0004\u0018\u00010Q2\n\b\u0002\u0010R\u001a\u0004\u0018\u00010S2\n\b\u0002\u0010T\u001a\u0004\u0018\u00010U2\n\b\u0002\u0010V\u001a\u0004\u0018\u00010W2\n\b\u0002\u0010X\u001a\u0004\u0018\u00010Y2\n\b\u0002\u0010Z\u001a\u0004\u0018\u00010[2\n\b\u0002\u0010\\\u001a\u0004\u0018\u00010]2\n\b\u0002\u0010^\u001a\u0004\u0018\u00010_2\n\b\u0002\u0010`\u001a\u0004\u0018\u00010a2\n\b\u0002\u0010b\u001a\u0004\u0018\u00010c2\n\b\u0002\u0010d\u001a\u0004\u0018\u00010e2\n\b\u0002\u0010f\u001a\u0004\u0018\u00010g2\n\b\u0002\u0010h\u001a\u0004\u0018\u00010i2\n\b\u0002\u0010j\u001a\u0004\u0018\u00010k2\n\b\u0002\u0010l\u001a\u0004\u0018\u00010m2\n\b\u0002\u0010n\u001a\u0004\u0018\u00010o2\n\b\u0002\u0010p\u001a\u0004\u0018\u00010q2\n\b\u0002\u0010r\u001a\u0004\u0018\u00010sHÆ\u0001J\u0016\u0010¢\u0002\u001a\u00030£\u00022\t\u0010¤\u0002\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\u000b\u0010¥\u0002\u001a\u00030¦\u0002HÖ\u0001J\u000b\u0010§\u0002\u001a\u00030¨\u0002HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\bv\u0010wR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\bx\u0010yR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\b\n\u0000\u001a\u0004\bz\u0010{R\u0013\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\b\n\u0000\u001a\u0004\b|\u0010}R\u0013\u0010\n\u001a\u0004\u0018\u00010\u000b¢\u0006\b\n\u0000\u001a\u0004\b~\u0010\u007fR\u0015\u0010\f\u001a\u0004\u0018\u00010\r¢\u0006\n\n\u0000\u001a\u0006\b\u0080\u0001\u0010\u0081\u0001R\u0015\u0010\u000e\u001a\u0004\u0018\u00010\u000f¢\u0006\n\n\u0000\u001a\u0006\b\u0082\u0001\u0010\u0083\u0001R\u0015\u0010\u0010\u001a\u0004\u0018\u00010\u0011¢\u0006\n\n\u0000\u001a\u0006\b\u0084\u0001\u0010\u0085\u0001R\u0015\u0010\u0012\u001a\u0004\u0018\u00010\u0013¢\u0006\n\n\u0000\u001a\u0006\b\u0086\u0001\u0010\u0087\u0001R\u0015\u0010\u0014\u001a\u0004\u0018\u00010\u0015¢\u0006\n\n\u0000\u001a\u0006\b\u0088\u0001\u0010\u0089\u0001R\u0015\u0010\u0016\u001a\u0004\u0018\u00010\u0017¢\u0006\n\n\u0000\u001a\u0006\b\u008a\u0001\u0010\u008b\u0001R\u0015\u0010\u0018\u001a\u0004\u0018\u00010\u0019¢\u0006\n\n\u0000\u001a\u0006\b\u008c\u0001\u0010\u008d\u0001R\u0015\u0010\u001a\u001a\u0004\u0018\u00010\u001b¢\u0006\n\n\u0000\u001a\u0006\b\u008e\u0001\u0010\u008f\u0001R\u0015\u0010\u001c\u001a\u0004\u0018\u00010\u001d¢\u0006\n\n\u0000\u001a\u0006\b\u0090\u0001\u0010\u0091\u0001R\u0015\u0010\u001e\u001a\u0004\u0018\u00010\u001f¢\u0006\n\n\u0000\u001a\u0006\b\u0092\u0001\u0010\u0093\u0001R\u0015\u0010 \u001a\u0004\u0018\u00010!¢\u0006\n\n\u0000\u001a\u0006\b\u0094\u0001\u0010\u0095\u0001R\u0015\u0010\"\u001a\u0004\u0018\u00010#¢\u0006\n\n\u0000\u001a\u0006\b\u0096\u0001\u0010\u0097\u0001R\u0015\u0010$\u001a\u0004\u0018\u00010%¢\u0006\n\n\u0000\u001a\u0006\b\u0098\u0001\u0010\u0099\u0001R\u0015\u0010&\u001a\u0004\u0018\u00010'¢\u0006\n\n\u0000\u001a\u0006\b\u009a\u0001\u0010\u009b\u0001R\u0015\u0010(\u001a\u0004\u0018\u00010)¢\u0006\n\n\u0000\u001a\u0006\b\u009c\u0001\u0010\u009d\u0001R\u0015\u0010*\u001a\u0004\u0018\u00010+¢\u0006\n\n\u0000\u001a\u0006\b\u009e\u0001\u0010\u009f\u0001R\u0015\u0010,\u001a\u0004\u0018\u00010-¢\u0006\n\n\u0000\u001a\u0006\b \u0001\u0010¡\u0001R\u0015\u0010.\u001a\u0004\u0018\u00010/¢\u0006\n\n\u0000\u001a\u0006\b¢\u0001\u0010£\u0001R\u0015\u00100\u001a\u0004\u0018\u000101¢\u0006\n\n\u0000\u001a\u0006\b¤\u0001\u0010¥\u0001R\u0015\u00102\u001a\u0004\u0018\u000103¢\u0006\n\n\u0000\u001a\u0006\b¦\u0001\u0010§\u0001R\u0015\u00104\u001a\u0004\u0018\u000105¢\u0006\n\n\u0000\u001a\u0006\b¨\u0001\u0010©\u0001R\u0015\u00106\u001a\u0004\u0018\u000107¢\u0006\n\n\u0000\u001a\u0006\bª\u0001\u0010«\u0001R\u0015\u00108\u001a\u0004\u0018\u000109¢\u0006\n\n\u0000\u001a\u0006\b¬\u0001\u0010\u00ad\u0001R\u0015\u0010:\u001a\u0004\u0018\u00010;¢\u0006\n\n\u0000\u001a\u0006\b®\u0001\u0010¯\u0001R\u0015\u0010<\u001a\u0004\u0018\u00010=¢\u0006\n\n\u0000\u001a\u0006\b°\u0001\u0010±\u0001R\u0015\u0010>\u001a\u0004\u0018\u00010?¢\u0006\n\n\u0000\u001a\u0006\b²\u0001\u0010³\u0001R\u0015\u0010@\u001a\u0004\u0018\u00010A¢\u0006\n\n\u0000\u001a\u0006\b´\u0001\u0010µ\u0001R\u0015\u0010B\u001a\u0004\u0018\u00010C¢\u0006\n\n\u0000\u001a\u0006\b¶\u0001\u0010·\u0001R\u0015\u0010D\u001a\u0004\u0018\u00010E¢\u0006\n\n\u0000\u001a\u0006\b¸\u0001\u0010¹\u0001R\u0015\u0010F\u001a\u0004\u0018\u00010G¢\u0006\n\n\u0000\u001a\u0006\bº\u0001\u0010»\u0001R\u0015\u0010H\u001a\u0004\u0018\u00010I¢\u0006\n\n\u0000\u001a\u0006\b¼\u0001\u0010½\u0001R\u0015\u0010J\u001a\u0004\u0018\u00010K¢\u0006\n\n\u0000\u001a\u0006\b¾\u0001\u0010¿\u0001R\u0015\u0010L\u001a\u0004\u0018\u00010M¢\u0006\n\n\u0000\u001a\u0006\bÀ\u0001\u0010Á\u0001R\u0015\u0010N\u001a\u0004\u0018\u00010O¢\u0006\n\n\u0000\u001a\u0006\bÂ\u0001\u0010Ã\u0001R\u0015\u0010P\u001a\u0004\u0018\u00010Q¢\u0006\n\n\u0000\u001a\u0006\bÄ\u0001\u0010Å\u0001R\u0015\u0010R\u001a\u0004\u0018\u00010S¢\u0006\n\n\u0000\u001a\u0006\bÆ\u0001\u0010Ç\u0001R\u0015\u0010T\u001a\u0004\u0018\u00010U¢\u0006\n\n\u0000\u001a\u0006\bÈ\u0001\u0010É\u0001R\u0015\u0010V\u001a\u0004\u0018\u00010W¢\u0006\n\n\u0000\u001a\u0006\bÊ\u0001\u0010Ë\u0001R\u0015\u0010X\u001a\u0004\u0018\u00010Y¢\u0006\n\n\u0000\u001a\u0006\bÌ\u0001\u0010Í\u0001R\u0015\u0010Z\u001a\u0004\u0018\u00010[¢\u0006\n\n\u0000\u001a\u0006\bÎ\u0001\u0010Ï\u0001R\u0015\u0010\\\u001a\u0004\u0018\u00010]¢\u0006\n\n\u0000\u001a\u0006\bÐ\u0001\u0010Ñ\u0001R\u0015\u0010^\u001a\u0004\u0018\u00010_¢\u0006\n\n\u0000\u001a\u0006\bÒ\u0001\u0010Ó\u0001R\u001a\u0010`\u001a\u0004\u0018\u00010a8\u0006X\u0087\u0004¢\u0006\n\n\u0000\u001a\u0006\bÔ\u0001\u0010Õ\u0001R\u001a\u0010b\u001a\u0004\u0018\u00010c8\u0006X\u0087\u0004¢\u0006\n\n\u0000\u001a\u0006\bÖ\u0001\u0010×\u0001R\u001a\u0010d\u001a\u0004\u0018\u00010e8\u0006X\u0087\u0004¢\u0006\n\n\u0000\u001a\u0006\bØ\u0001\u0010Ù\u0001R\u001a\u0010f\u001a\u0004\u0018\u00010g8\u0006X\u0087\u0004¢\u0006\n\n\u0000\u001a\u0006\bÚ\u0001\u0010Û\u0001R\u001a\u0010h\u001a\u0004\u0018\u00010i8\u0006X\u0087\u0004¢\u0006\n\n\u0000\u001a\u0006\bÜ\u0001\u0010Ý\u0001R\u001a\u0010j\u001a\u0004\u0018\u00010k8\u0006X\u0087\u0004¢\u0006\n\n\u0000\u001a\u0006\bÞ\u0001\u0010ß\u0001R\u0015\u0010l\u001a\u0004\u0018\u00010m¢\u0006\n\n\u0000\u001a\u0006\bà\u0001\u0010á\u0001R\u0015\u0010n\u001a\u0004\u0018\u00010o¢\u0006\n\n\u0000\u001a\u0006\bâ\u0001\u0010ã\u0001R\u0015\u0010p\u001a\u0004\u0018\u00010q¢\u0006\n\n\u0000\u001a\u0006\bä\u0001\u0010å\u0001R\u0015\u0010r\u001a\u0004\u0018\u00010s¢\u0006\n\n\u0000\u001a\u0006\bæ\u0001\u0010ç\u0001¨\u0006©\u0002"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ChartIndicatorSetting;", "", "boll", "Lsp/aicoin_kline/core/indicator/config/BollRemote;", "aiAggtrade", "Lsp/aicoin_kline/core/indicator/config/AiAggtradeRemote;", DublinCore.PREFIX_DC, "Lsp/aicoin_kline/core/indicator/config/DCRemote;", "ene", "Lsp/aicoin_kline/core/indicator/config/ENERemote;", "ichimoku", "Lsp/aicoin_kline/core/indicator/config/IchimokuRemote;", "kc", "Lsp/aicoin_kline/core/indicator/config/KCRemote;", "sar", "Lsp/aicoin_kline/core/indicator/config/SARRemote;", "ma", "Lsp/aicoin_kline/core/indicator/config/MARemote;", "ema", "Lsp/aicoin_kline/core/indicator/config/EMARemote;", "alligator", "Lsp/aicoin_kline/core/indicator/config/AlligatorRemote;", "bbi", "Lsp/aicoin_kline/core/indicator/config/BBIRemote;", "td", "Lsp/aicoin_kline/core/indicator/config/TDRemote;", "volume", "Lsp/aicoin_kline/core/indicator/config/VolumeRemote;", "macd", "Lsp/aicoin_kline/core/indicator/config/MACDRemote;", "kdj", "Lsp/aicoin_kline/core/indicator/config/KDJRemote;", "rsi", "Lsp/aicoin_kline/core/indicator/config/RsiRemote;", "obv", "Lsp/aicoin_kline/core/indicator/config/ObvRemote;", "stochrsi", "Lsp/aicoin_kline/core/indicator/config/StochRSIRemote;", "trix", "Lsp/aicoin_kline/core/indicator/config/TrixRemote;", "wr", "Lsp/aicoin_kline/core/indicator/config/WRRemote;", "cci", "Lsp/aicoin_kline/core/indicator/config/CCIRemote;", "roc", "Lsp/aicoin_kline/core/indicator/config/ROCRemote;", "atr", "Lsp/aicoin_kline/core/indicator/config/AtrRemote;", "dmi", "Lsp/aicoin_kline/core/indicator/config/DmiRemote;", "vr", "Lsp/aicoin_kline/core/indicator/config/VrRemote;", "psy", "Lsp/aicoin_kline/core/indicator/config/PsyRemote;", "bias", "Lsp/aicoin_kline/core/indicator/config/BiasRemote;", "smi", "Lsp/aicoin_kline/core/indicator/config/SmiRemote;", "skdj", "Lsp/aicoin_kline/core/indicator/config/SkdjRemote;", "dma", "Lsp/aicoin_kline/core/indicator/config/DmaRemote;", "mtm", "Lsp/aicoin_kline/core/indicator/config/MtmRemote;", "bbw", "Lsp/aicoin_kline/core/indicator/config/BbwRemote;", "fundflow", "Lsp/aicoin_kline/core/indicator/config/FundFlowRemote;", "position", "Lsp/aicoin_kline/core/indicator/config/PositionRemote;", "ttsi", "Lsp/aicoin_kline/core/indicator/config/TTSIRemote;", "ttmu", "Lsp/aicoin_kline/core/indicator/config/TTMURemote;", "brar", "Lsp/aicoin_kline/core/indicator/config/BRARRemote;", "emv", "Lsp/aicoin_kline/core/indicator/config/EMVRemote;", "mfi", "Lsp/aicoin_kline/core/indicator/config/MFIRemote;", "dpo", "Lsp/aicoin_kline/core/indicator/config/DPORemote;", "ao", "Lsp/aicoin_kline/core/indicator/config/AORemote;", "lsur", "Lsp/aicoin_kline/core/indicator/config/LSURRemote;", "basis", "Lsp/aicoin_kline/core/indicator/config/BasisRemote;", "tvolume", "Lsp/aicoin_kline/core/indicator/config/TVolumeRemote;", "ftbs", "Lsp/aicoin_kline/core/indicator/config/FTBSRemote;", "mlr", "Lsp/aicoin_kline/core/indicator/config/MLRRemote;", "bsv", "Lsp/aicoin_kline/core/indicator/config/BSVRemote;", "aifdi", "Lsp/aicoin_kline/core/indicator/config/AiFDIRemote;", "aipd", "Lsp/aicoin_kline/core/indicator/config/AiPDRemote;", "aili", "Lsp/aicoin_kline/core/indicator/config/AiLIRemote;", "aibsi", "Lsp/aicoin_kline/core/indicator/config/AiBsiRemote;", "ainetvol", "Lsp/aicoin_kline/core/indicator/config/AiNetVolRemote;", "aibst", "Lsp/aicoin_kline/core/indicator/config/AiBstRemote;", "fr", "Lsp/aicoin_kline/core/indicator/config/FRRemote;", "pfr", "Lsp/aicoin_kline/core/indicator/config/PFRRemote;", "vpvr", "Lsp/aicoin_kline/core/indicator/config/VPVRRemote;", "liqheatmap", "Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote;", "<init>", "(Lsp/aicoin_kline/core/indicator/config/BollRemote;Lsp/aicoin_kline/core/indicator/config/AiAggtradeRemote;Lsp/aicoin_kline/core/indicator/config/DCRemote;Lsp/aicoin_kline/core/indicator/config/ENERemote;Lsp/aicoin_kline/core/indicator/config/IchimokuRemote;Lsp/aicoin_kline/core/indicator/config/KCRemote;Lsp/aicoin_kline/core/indicator/config/SARRemote;Lsp/aicoin_kline/core/indicator/config/MARemote;Lsp/aicoin_kline/core/indicator/config/EMARemote;Lsp/aicoin_kline/core/indicator/config/AlligatorRemote;Lsp/aicoin_kline/core/indicator/config/BBIRemote;Lsp/aicoin_kline/core/indicator/config/TDRemote;Lsp/aicoin_kline/core/indicator/config/VolumeRemote;Lsp/aicoin_kline/core/indicator/config/MACDRemote;Lsp/aicoin_kline/core/indicator/config/KDJRemote;Lsp/aicoin_kline/core/indicator/config/RsiRemote;Lsp/aicoin_kline/core/indicator/config/ObvRemote;Lsp/aicoin_kline/core/indicator/config/StochRSIRemote;Lsp/aicoin_kline/core/indicator/config/TrixRemote;Lsp/aicoin_kline/core/indicator/config/WRRemote;Lsp/aicoin_kline/core/indicator/config/CCIRemote;Lsp/aicoin_kline/core/indicator/config/ROCRemote;Lsp/aicoin_kline/core/indicator/config/AtrRemote;Lsp/aicoin_kline/core/indicator/config/DmiRemote;Lsp/aicoin_kline/core/indicator/config/VrRemote;Lsp/aicoin_kline/core/indicator/config/PsyRemote;Lsp/aicoin_kline/core/indicator/config/BiasRemote;Lsp/aicoin_kline/core/indicator/config/SmiRemote;Lsp/aicoin_kline/core/indicator/config/SkdjRemote;Lsp/aicoin_kline/core/indicator/config/DmaRemote;Lsp/aicoin_kline/core/indicator/config/MtmRemote;Lsp/aicoin_kline/core/indicator/config/BbwRemote;Lsp/aicoin_kline/core/indicator/config/FundFlowRemote;Lsp/aicoin_kline/core/indicator/config/PositionRemote;Lsp/aicoin_kline/core/indicator/config/TTSIRemote;Lsp/aicoin_kline/core/indicator/config/TTMURemote;Lsp/aicoin_kline/core/indicator/config/BRARRemote;Lsp/aicoin_kline/core/indicator/config/EMVRemote;Lsp/aicoin_kline/core/indicator/config/MFIRemote;Lsp/aicoin_kline/core/indicator/config/DPORemote;Lsp/aicoin_kline/core/indicator/config/AORemote;Lsp/aicoin_kline/core/indicator/config/LSURRemote;Lsp/aicoin_kline/core/indicator/config/BasisRemote;Lsp/aicoin_kline/core/indicator/config/TVolumeRemote;Lsp/aicoin_kline/core/indicator/config/FTBSRemote;Lsp/aicoin_kline/core/indicator/config/MLRRemote;Lsp/aicoin_kline/core/indicator/config/BSVRemote;Lsp/aicoin_kline/core/indicator/config/AiFDIRemote;Lsp/aicoin_kline/core/indicator/config/AiPDRemote;Lsp/aicoin_kline/core/indicator/config/AiLIRemote;Lsp/aicoin_kline/core/indicator/config/AiBsiRemote;Lsp/aicoin_kline/core/indicator/config/AiNetVolRemote;Lsp/aicoin_kline/core/indicator/config/AiBstRemote;Lsp/aicoin_kline/core/indicator/config/FRRemote;Lsp/aicoin_kline/core/indicator/config/PFRRemote;Lsp/aicoin_kline/core/indicator/config/VPVRRemote;Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote;)V", "getBoll", "()Lsp/aicoin_kline/core/indicator/config/BollRemote;", "getAiAggtrade", "()Lsp/aicoin_kline/core/indicator/config/AiAggtradeRemote;", "getDc", "()Lsp/aicoin_kline/core/indicator/config/DCRemote;", "getEne", "()Lsp/aicoin_kline/core/indicator/config/ENERemote;", "getIchimoku", "()Lsp/aicoin_kline/core/indicator/config/IchimokuRemote;", "getKc", "()Lsp/aicoin_kline/core/indicator/config/KCRemote;", "getSar", "()Lsp/aicoin_kline/core/indicator/config/SARRemote;", "getMa", "()Lsp/aicoin_kline/core/indicator/config/MARemote;", "getEma", "()Lsp/aicoin_kline/core/indicator/config/EMARemote;", "getAlligator", "()Lsp/aicoin_kline/core/indicator/config/AlligatorRemote;", "getBbi", "()Lsp/aicoin_kline/core/indicator/config/BBIRemote;", "getTd", "()Lsp/aicoin_kline/core/indicator/config/TDRemote;", "getVolume", "()Lsp/aicoin_kline/core/indicator/config/VolumeRemote;", "getMacd", "()Lsp/aicoin_kline/core/indicator/config/MACDRemote;", "getKdj", "()Lsp/aicoin_kline/core/indicator/config/KDJRemote;", "getRsi", "()Lsp/aicoin_kline/core/indicator/config/RsiRemote;", "getObv", "()Lsp/aicoin_kline/core/indicator/config/ObvRemote;", "getStochrsi", "()Lsp/aicoin_kline/core/indicator/config/StochRSIRemote;", "getTrix", "()Lsp/aicoin_kline/core/indicator/config/TrixRemote;", "getWr", "()Lsp/aicoin_kline/core/indicator/config/WRRemote;", "getCci", "()Lsp/aicoin_kline/core/indicator/config/CCIRemote;", "getRoc", "()Lsp/aicoin_kline/core/indicator/config/ROCRemote;", "getAtr", "()Lsp/aicoin_kline/core/indicator/config/AtrRemote;", "getDmi", "()Lsp/aicoin_kline/core/indicator/config/DmiRemote;", "getVr", "()Lsp/aicoin_kline/core/indicator/config/VrRemote;", "getPsy", "()Lsp/aicoin_kline/core/indicator/config/PsyRemote;", "getBias", "()Lsp/aicoin_kline/core/indicator/config/BiasRemote;", "getSmi", "()Lsp/aicoin_kline/core/indicator/config/SmiRemote;", "getSkdj", "()Lsp/aicoin_kline/core/indicator/config/SkdjRemote;", "getDma", "()Lsp/aicoin_kline/core/indicator/config/DmaRemote;", "getMtm", "()Lsp/aicoin_kline/core/indicator/config/MtmRemote;", "getBbw", "()Lsp/aicoin_kline/core/indicator/config/BbwRemote;", "getFundflow", "()Lsp/aicoin_kline/core/indicator/config/FundFlowRemote;", "getPosition", "()Lsp/aicoin_kline/core/indicator/config/PositionRemote;", "getTtsi", "()Lsp/aicoin_kline/core/indicator/config/TTSIRemote;", "getTtmu", "()Lsp/aicoin_kline/core/indicator/config/TTMURemote;", "getBrar", "()Lsp/aicoin_kline/core/indicator/config/BRARRemote;", "getEmv", "()Lsp/aicoin_kline/core/indicator/config/EMVRemote;", "getMfi", "()Lsp/aicoin_kline/core/indicator/config/MFIRemote;", "getDpo", "()Lsp/aicoin_kline/core/indicator/config/DPORemote;", "getAo", "()Lsp/aicoin_kline/core/indicator/config/AORemote;", "getLsur", "()Lsp/aicoin_kline/core/indicator/config/LSURRemote;", "getBasis", "()Lsp/aicoin_kline/core/indicator/config/BasisRemote;", "getTvolume", "()Lsp/aicoin_kline/core/indicator/config/TVolumeRemote;", "getFtbs", "()Lsp/aicoin_kline/core/indicator/config/FTBSRemote;", "getMlr", "()Lsp/aicoin_kline/core/indicator/config/MLRRemote;", "getBsv", "()Lsp/aicoin_kline/core/indicator/config/BSVRemote;", "getAifdi", "()Lsp/aicoin_kline/core/indicator/config/AiFDIRemote;", "getAipd", "()Lsp/aicoin_kline/core/indicator/config/AiPDRemote;", "getAili", "()Lsp/aicoin_kline/core/indicator/config/AiLIRemote;", "getAibsi", "()Lsp/aicoin_kline/core/indicator/config/AiBsiRemote;", "getAinetvol", "()Lsp/aicoin_kline/core/indicator/config/AiNetVolRemote;", "getAibst", "()Lsp/aicoin_kline/core/indicator/config/AiBstRemote;", "getFr", "()Lsp/aicoin_kline/core/indicator/config/FRRemote;", "getPfr", "()Lsp/aicoin_kline/core/indicator/config/PFRRemote;", "getVpvr", "()Lsp/aicoin_kline/core/indicator/config/VPVRRemote;", "getLiqheatmap", "()Lsp/aicoin_kline/core/indicator/config/LiqHeatmapRemote;", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component19", "component20", "component21", "component22", "component23", "component24", "component25", "component26", "component27", "component28", "component29", "component30", "component31", "component32", "component33", "component34", "component35", "component36", "component37", "component38", "component39", "component40", "component41", "component42", "component43", "component44", "component45", "component46", "component47", "component48", "component49", "component50", "component51", "component52", "component53", "component54", "component55", "component56", "component57", "copy", "equals", "", "other", "hashCode", "", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ChartIndicatorSetting {

    @SerializedName("ai-aggtrade")
    private final AiAggtradeRemote aiAggtrade;

    @SerializedName("ai-bsi")
    private final AiBsiRemote aibsi;

    @SerializedName("ai-bst")
    private final AiBstRemote aibst;

    @SerializedName("ai-fdi")
    private final AiFDIRemote aifdi;

    @SerializedName("ai-li")
    private final AiLIRemote aili;

    @SerializedName("ai-netvol")
    private final AiNetVolRemote ainetvol;

    @SerializedName("ai-pd")
    private final AiPDRemote aipd;
    private final AlligatorRemote alligator;
    private final AORemote ao;
    private final AtrRemote atr;
    private final BasisRemote basis;
    private final BBIRemote bbi;
    private final BbwRemote bbw;
    private final BiasRemote bias;
    private final BollRemote boll;
    private final BRARRemote brar;
    private final BSVRemote bsv;
    private final CCIRemote cci;
    private final DCRemote dc;
    private final DmaRemote dma;
    private final DmiRemote dmi;
    private final DPORemote dpo;
    private final EMARemote ema;
    private final EMVRemote emv;
    private final ENERemote ene;
    private final FRRemote fr;
    private final FTBSRemote ftbs;
    private final FundFlowRemote fundflow;
    private final IchimokuRemote ichimoku;
    private final KCRemote kc;
    private final KDJRemote kdj;
    private final LiqHeatmapRemote liqheatmap;
    private final LSURRemote lsur;
    private final MARemote ma;
    private final MACDRemote macd;
    private final MFIRemote mfi;
    private final MLRRemote mlr;
    private final MtmRemote mtm;
    private final ObvRemote obv;
    private final PFRRemote pfr;
    private final PositionRemote position;
    private final PsyRemote psy;
    private final ROCRemote roc;
    private final RsiRemote rsi;
    private final SARRemote sar;
    private final SkdjRemote skdj;
    private final SmiRemote smi;
    private final StochRSIRemote stochrsi;
    private final TDRemote td;
    private final TrixRemote trix;
    private final TTMURemote ttmu;
    private final TTSIRemote ttsi;
    private final TVolumeRemote tvolume;
    private final VolumeRemote volume;
    private final VPVRRemote vpvr;
    private final VrRemote vr;
    private final WRRemote wr;

    public ChartIndicatorSetting() {
        this(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554431, null);
    }

    public ChartIndicatorSetting(BollRemote bollRemote, AiAggtradeRemote aiAggtradeRemote, DCRemote dCRemote, ENERemote eNERemote, IchimokuRemote ichimokuRemote, KCRemote kCRemote, SARRemote sARRemote, MARemote mARemote, EMARemote eMARemote, AlligatorRemote alligatorRemote, BBIRemote bBIRemote, TDRemote tDRemote, VolumeRemote volumeRemote, MACDRemote mACDRemote, KDJRemote kDJRemote, RsiRemote rsiRemote, ObvRemote obvRemote, StochRSIRemote stochRSIRemote, TrixRemote trixRemote, WRRemote wRRemote, CCIRemote cCIRemote, ROCRemote rOCRemote, AtrRemote atrRemote, DmiRemote dmiRemote, VrRemote vrRemote, PsyRemote psyRemote, BiasRemote biasRemote, SmiRemote smiRemote, SkdjRemote skdjRemote, DmaRemote dmaRemote, MtmRemote mtmRemote, BbwRemote bbwRemote, FundFlowRemote fundFlowRemote, PositionRemote positionRemote, TTSIRemote tTSIRemote, TTMURemote tTMURemote, BRARRemote bRARRemote, EMVRemote eMVRemote, MFIRemote mFIRemote, DPORemote dPORemote, AORemote aORemote, LSURRemote lSURRemote, BasisRemote basisRemote, TVolumeRemote tVolumeRemote, FTBSRemote fTBSRemote, MLRRemote mLRRemote, BSVRemote bSVRemote, AiFDIRemote aiFDIRemote, AiPDRemote aiPDRemote, AiLIRemote aiLIRemote, AiBsiRemote aiBsiRemote, AiNetVolRemote aiNetVolRemote, AiBstRemote aiBstRemote, FRRemote fRRemote, PFRRemote pFRRemote, VPVRRemote vPVRRemote, LiqHeatmapRemote liqHeatmapRemote) {
        this.boll = bollRemote;
        this.aiAggtrade = aiAggtradeRemote;
        this.dc = dCRemote;
        this.ene = eNERemote;
        this.ichimoku = ichimokuRemote;
        this.kc = kCRemote;
        this.sar = sARRemote;
        this.ma = mARemote;
        this.ema = eMARemote;
        this.alligator = alligatorRemote;
        this.bbi = bBIRemote;
        this.td = tDRemote;
        this.volume = volumeRemote;
        this.macd = mACDRemote;
        this.kdj = kDJRemote;
        this.rsi = rsiRemote;
        this.obv = obvRemote;
        this.stochrsi = stochRSIRemote;
        this.trix = trixRemote;
        this.wr = wRRemote;
        this.cci = cCIRemote;
        this.roc = rOCRemote;
        this.atr = atrRemote;
        this.dmi = dmiRemote;
        this.vr = vrRemote;
        this.psy = psyRemote;
        this.bias = biasRemote;
        this.smi = smiRemote;
        this.skdj = skdjRemote;
        this.dma = dmaRemote;
        this.mtm = mtmRemote;
        this.bbw = bbwRemote;
        this.fundflow = fundFlowRemote;
        this.position = positionRemote;
        this.ttsi = tTSIRemote;
        this.ttmu = tTMURemote;
        this.brar = bRARRemote;
        this.emv = eMVRemote;
        this.mfi = mFIRemote;
        this.dpo = dPORemote;
        this.ao = aORemote;
        this.lsur = lSURRemote;
        this.basis = basisRemote;
        this.tvolume = tVolumeRemote;
        this.ftbs = fTBSRemote;
        this.mlr = mLRRemote;
        this.bsv = bSVRemote;
        this.aifdi = aiFDIRemote;
        this.aipd = aiPDRemote;
        this.aili = aiLIRemote;
        this.aibsi = aiBsiRemote;
        this.ainetvol = aiNetVolRemote;
        this.aibst = aiBstRemote;
        this.fr = fRRemote;
        this.pfr = pFRRemote;
        this.vpvr = vPVRRemote;
        this.liqheatmap = liqHeatmapRemote;
    }

    /* JADX WARN: Illegal instructions before constructor call */
    public /* synthetic */ ChartIndicatorSetting(BollRemote bollRemote, AiAggtradeRemote aiAggtradeRemote, DCRemote dCRemote, ENERemote eNERemote, IchimokuRemote ichimokuRemote, KCRemote kCRemote, SARRemote sARRemote, MARemote mARemote, EMARemote eMARemote, AlligatorRemote alligatorRemote, BBIRemote bBIRemote, TDRemote tDRemote, VolumeRemote volumeRemote, MACDRemote mACDRemote, KDJRemote kDJRemote, RsiRemote rsiRemote, ObvRemote obvRemote, StochRSIRemote stochRSIRemote, TrixRemote trixRemote, WRRemote wRRemote, CCIRemote cCIRemote, ROCRemote rOCRemote, AtrRemote atrRemote, DmiRemote dmiRemote, VrRemote vrRemote, PsyRemote psyRemote, BiasRemote biasRemote, SmiRemote smiRemote, SkdjRemote skdjRemote, DmaRemote dmaRemote, MtmRemote mtmRemote, BbwRemote bbwRemote, FundFlowRemote fundFlowRemote, PositionRemote positionRemote, TTSIRemote tTSIRemote, TTMURemote tTMURemote, BRARRemote bRARRemote, EMVRemote eMVRemote, MFIRemote mFIRemote, DPORemote dPORemote, AORemote aORemote, LSURRemote lSURRemote, BasisRemote basisRemote, TVolumeRemote tVolumeRemote, FTBSRemote fTBSRemote, MLRRemote mLRRemote, BSVRemote bSVRemote, AiFDIRemote aiFDIRemote, AiPDRemote aiPDRemote, AiLIRemote aiLIRemote, AiBsiRemote aiBsiRemote, AiNetVolRemote aiNetVolRemote, AiBstRemote aiBstRemote, FRRemote fRRemote, PFRRemote pFRRemote, VPVRRemote vPVRRemote, LiqHeatmapRemote liqHeatmapRemote, int i10, int i11, DefaultConstructorMarker defaultConstructorMarker) {
        BollRemote bollRemote2 = (i10 & 1) != 0 ? null : bollRemote;
        this(bollRemote2, (i10 & 2) != 0 ? null : aiAggtradeRemote, (i10 & 4) != 0 ? null : dCRemote, (i10 & 8) != 0 ? null : eNERemote, (i10 & 16) != 0 ? null : ichimokuRemote, (i10 & 32) != 0 ? null : kCRemote, (i10 & 64) != 0 ? null : sARRemote, (i10 & 128) != 0 ? null : mARemote, (i10 & 256) != 0 ? null : eMARemote, (i10 & 512) != 0 ? null : alligatorRemote, (i10 & 1024) != 0 ? null : bBIRemote, (i10 & 2048) != 0 ? null : tDRemote, (i10 & 4096) != 0 ? null : volumeRemote, (i10 & 8192) != 0 ? null : mACDRemote, (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? null : kDJRemote, (i10 & 32768) != 0 ? null : rsiRemote, (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? null : obvRemote, (i10 & 131072) != 0 ? null : stochRSIRemote, (i10 & 262144) != 0 ? null : trixRemote, (i10 & SQLiteGlobal.journalSizeLimit) != 0 ? null : wRRemote, (i10 & 1048576) != 0 ? null : cCIRemote, (i10 & 2097152) != 0 ? null : rOCRemote, (i10 & 4194304) != 0 ? null : atrRemote, (i10 & 8388608) != 0 ? null : dmiRemote, (i10 & Http2Connection.OKHTTP_CLIENT_WINDOW_SIZE) != 0 ? null : vrRemote, (i10 & 33554432) != 0 ? null : psyRemote, (i10 & 67108864) != 0 ? null : biasRemote, (i10 & 134217728) != 0 ? null : smiRemote, (i10 & 268435456) != 0 ? null : skdjRemote, (i10 & SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING) != 0 ? null : dmaRemote, (i10 & 1073741824) != 0 ? null : mtmRemote, (i10 & Integer.MIN_VALUE) != 0 ? null : bbwRemote, (i11 & 1) != 0 ? null : fundFlowRemote, (i11 & 2) != 0 ? null : positionRemote, (i11 & 4) != 0 ? null : tTSIRemote, (i11 & 8) != 0 ? null : tTMURemote, (i11 & 16) != 0 ? null : bRARRemote, (i11 & 32) != 0 ? null : eMVRemote, (i11 & 64) != 0 ? null : mFIRemote, (i11 & 128) != 0 ? null : dPORemote, (i11 & 256) != 0 ? null : aORemote, (i11 & 512) != 0 ? null : lSURRemote, (i11 & 1024) != 0 ? null : basisRemote, (i11 & 2048) != 0 ? null : tVolumeRemote, (i11 & 4096) != 0 ? null : fTBSRemote, (i11 & 8192) != 0 ? null : mLRRemote, (i11 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? null : bSVRemote, (i11 & 32768) != 0 ? null : aiFDIRemote, (i11 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? null : aiPDRemote, (i11 & 131072) != 0 ? null : aiLIRemote, (i11 & 262144) != 0 ? null : aiBsiRemote, (i11 & SQLiteGlobal.journalSizeLimit) != 0 ? null : aiNetVolRemote, (i11 & 1048576) != 0 ? null : aiBstRemote, (i11 & 2097152) != 0 ? null : fRRemote, (i11 & 4194304) != 0 ? null : pFRRemote, (i11 & 8388608) != 0 ? null : vPVRRemote, (i11 & Http2Connection.OKHTTP_CLIENT_WINDOW_SIZE) != 0 ? null : liqHeatmapRemote);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final BollRemote getBoll() {
        return this.boll;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final AlligatorRemote getAlligator() {
        return this.alligator;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final BBIRemote getBbi() {
        return this.bbi;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final TDRemote getTd() {
        return this.td;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final VolumeRemote getVolume() {
        return this.volume;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final MACDRemote getMacd() {
        return this.macd;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final KDJRemote getKdj() {
        return this.kdj;
    }

    /* JADX INFO: renamed from: component16, reason: from getter */
    public final RsiRemote getRsi() {
        return this.rsi;
    }

    /* JADX INFO: renamed from: component17, reason: from getter */
    public final ObvRemote getObv() {
        return this.obv;
    }

    /* JADX INFO: renamed from: component18, reason: from getter */
    public final StochRSIRemote getStochrsi() {
        return this.stochrsi;
    }

    /* JADX INFO: renamed from: component19, reason: from getter */
    public final TrixRemote getTrix() {
        return this.trix;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final AiAggtradeRemote getAiAggtrade() {
        return this.aiAggtrade;
    }

    /* JADX INFO: renamed from: component20, reason: from getter */
    public final WRRemote getWr() {
        return this.wr;
    }

    /* JADX INFO: renamed from: component21, reason: from getter */
    public final CCIRemote getCci() {
        return this.cci;
    }

    /* JADX INFO: renamed from: component22, reason: from getter */
    public final ROCRemote getRoc() {
        return this.roc;
    }

    /* JADX INFO: renamed from: component23, reason: from getter */
    public final AtrRemote getAtr() {
        return this.atr;
    }

    /* JADX INFO: renamed from: component24, reason: from getter */
    public final DmiRemote getDmi() {
        return this.dmi;
    }

    /* JADX INFO: renamed from: component25, reason: from getter */
    public final VrRemote getVr() {
        return this.vr;
    }

    /* JADX INFO: renamed from: component26, reason: from getter */
    public final PsyRemote getPsy() {
        return this.psy;
    }

    /* JADX INFO: renamed from: component27, reason: from getter */
    public final BiasRemote getBias() {
        return this.bias;
    }

    /* JADX INFO: renamed from: component28, reason: from getter */
    public final SmiRemote getSmi() {
        return this.smi;
    }

    /* JADX INFO: renamed from: component29, reason: from getter */
    public final SkdjRemote getSkdj() {
        return this.skdj;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final DCRemote getDc() {
        return this.dc;
    }

    /* JADX INFO: renamed from: component30, reason: from getter */
    public final DmaRemote getDma() {
        return this.dma;
    }

    /* JADX INFO: renamed from: component31, reason: from getter */
    public final MtmRemote getMtm() {
        return this.mtm;
    }

    /* JADX INFO: renamed from: component32, reason: from getter */
    public final BbwRemote getBbw() {
        return this.bbw;
    }

    /* JADX INFO: renamed from: component33, reason: from getter */
    public final FundFlowRemote getFundflow() {
        return this.fundflow;
    }

    /* JADX INFO: renamed from: component34, reason: from getter */
    public final PositionRemote getPosition() {
        return this.position;
    }

    /* JADX INFO: renamed from: component35, reason: from getter */
    public final TTSIRemote getTtsi() {
        return this.ttsi;
    }

    /* JADX INFO: renamed from: component36, reason: from getter */
    public final TTMURemote getTtmu() {
        return this.ttmu;
    }

    /* JADX INFO: renamed from: component37, reason: from getter */
    public final BRARRemote getBrar() {
        return this.brar;
    }

    /* JADX INFO: renamed from: component38, reason: from getter */
    public final EMVRemote getEmv() {
        return this.emv;
    }

    /* JADX INFO: renamed from: component39, reason: from getter */
    public final MFIRemote getMfi() {
        return this.mfi;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final ENERemote getEne() {
        return this.ene;
    }

    /* JADX INFO: renamed from: component40, reason: from getter */
    public final DPORemote getDpo() {
        return this.dpo;
    }

    /* JADX INFO: renamed from: component41, reason: from getter */
    public final AORemote getAo() {
        return this.ao;
    }

    /* JADX INFO: renamed from: component42, reason: from getter */
    public final LSURRemote getLsur() {
        return this.lsur;
    }

    /* JADX INFO: renamed from: component43, reason: from getter */
    public final BasisRemote getBasis() {
        return this.basis;
    }

    /* JADX INFO: renamed from: component44, reason: from getter */
    public final TVolumeRemote getTvolume() {
        return this.tvolume;
    }

    /* JADX INFO: renamed from: component45, reason: from getter */
    public final FTBSRemote getFtbs() {
        return this.ftbs;
    }

    /* JADX INFO: renamed from: component46, reason: from getter */
    public final MLRRemote getMlr() {
        return this.mlr;
    }

    /* JADX INFO: renamed from: component47, reason: from getter */
    public final BSVRemote getBsv() {
        return this.bsv;
    }

    /* JADX INFO: renamed from: component48, reason: from getter */
    public final AiFDIRemote getAifdi() {
        return this.aifdi;
    }

    /* JADX INFO: renamed from: component49, reason: from getter */
    public final AiPDRemote getAipd() {
        return this.aipd;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final IchimokuRemote getIchimoku() {
        return this.ichimoku;
    }

    /* JADX INFO: renamed from: component50, reason: from getter */
    public final AiLIRemote getAili() {
        return this.aili;
    }

    /* JADX INFO: renamed from: component51, reason: from getter */
    public final AiBsiRemote getAibsi() {
        return this.aibsi;
    }

    /* JADX INFO: renamed from: component52, reason: from getter */
    public final AiNetVolRemote getAinetvol() {
        return this.ainetvol;
    }

    /* JADX INFO: renamed from: component53, reason: from getter */
    public final AiBstRemote getAibst() {
        return this.aibst;
    }

    /* JADX INFO: renamed from: component54, reason: from getter */
    public final FRRemote getFr() {
        return this.fr;
    }

    /* JADX INFO: renamed from: component55, reason: from getter */
    public final PFRRemote getPfr() {
        return this.pfr;
    }

    /* JADX INFO: renamed from: component56, reason: from getter */
    public final VPVRRemote getVpvr() {
        return this.vpvr;
    }

    /* JADX INFO: renamed from: component57, reason: from getter */
    public final LiqHeatmapRemote getLiqheatmap() {
        return this.liqheatmap;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final KCRemote getKc() {
        return this.kc;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final SARRemote getSar() {
        return this.sar;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final MARemote getMa() {
        return this.ma;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final EMARemote getEma() {
        return this.ema;
    }

    public final ChartIndicatorSetting copy(BollRemote boll, AiAggtradeRemote aiAggtrade, DCRemote dc2, ENERemote ene, IchimokuRemote ichimoku, KCRemote kc2, SARRemote sar, MARemote ma2, EMARemote ema, AlligatorRemote alligator, BBIRemote bbi, TDRemote td2, VolumeRemote volume, MACDRemote macd, KDJRemote kdj, RsiRemote rsi, ObvRemote obv, StochRSIRemote stochrsi, TrixRemote trix, WRRemote wr, CCIRemote cci, ROCRemote roc, AtrRemote atr, DmiRemote dmi, VrRemote vr, PsyRemote psy, BiasRemote bias, SmiRemote smi, SkdjRemote skdj, DmaRemote dma, MtmRemote mtm, BbwRemote bbw, FundFlowRemote fundflow, PositionRemote position, TTSIRemote ttsi, TTMURemote ttmu, BRARRemote brar, EMVRemote emv, MFIRemote mfi, DPORemote dpo, AORemote ao, LSURRemote lsur, BasisRemote basis, TVolumeRemote tvolume, FTBSRemote ftbs, MLRRemote mlr, BSVRemote bsv, AiFDIRemote aifdi, AiPDRemote aipd, AiLIRemote aili, AiBsiRemote aibsi, AiNetVolRemote ainetvol, AiBstRemote aibst, FRRemote fr, PFRRemote pfr, VPVRRemote vpvr, LiqHeatmapRemote liqheatmap) {
        return new ChartIndicatorSetting(boll, aiAggtrade, dc2, ene, ichimoku, kc2, sar, ma2, ema, alligator, bbi, td2, volume, macd, kdj, rsi, obv, stochrsi, trix, wr, cci, roc, atr, dmi, vr, psy, bias, smi, skdj, dma, mtm, bbw, fundflow, position, ttsi, ttmu, brar, emv, mfi, dpo, ao, lsur, basis, tvolume, ftbs, mlr, bsv, aifdi, aipd, aili, aibsi, ainetvol, aibst, fr, pfr, vpvr, liqheatmap);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ChartIndicatorSetting)) {
            return false;
        }
        ChartIndicatorSetting chartIndicatorSetting = (ChartIndicatorSetting) other;
        return AbstractC7609s.f(this.boll, chartIndicatorSetting.boll) && AbstractC7609s.f(this.aiAggtrade, chartIndicatorSetting.aiAggtrade) && AbstractC7609s.f(this.dc, chartIndicatorSetting.dc) && AbstractC7609s.f(this.ene, chartIndicatorSetting.ene) && AbstractC7609s.f(this.ichimoku, chartIndicatorSetting.ichimoku) && AbstractC7609s.f(this.kc, chartIndicatorSetting.kc) && AbstractC7609s.f(this.sar, chartIndicatorSetting.sar) && AbstractC7609s.f(this.ma, chartIndicatorSetting.ma) && AbstractC7609s.f(this.ema, chartIndicatorSetting.ema) && AbstractC7609s.f(this.alligator, chartIndicatorSetting.alligator) && AbstractC7609s.f(this.bbi, chartIndicatorSetting.bbi) && AbstractC7609s.f(this.td, chartIndicatorSetting.td) && AbstractC7609s.f(this.volume, chartIndicatorSetting.volume) && AbstractC7609s.f(this.macd, chartIndicatorSetting.macd) && AbstractC7609s.f(this.kdj, chartIndicatorSetting.kdj) && AbstractC7609s.f(this.rsi, chartIndicatorSetting.rsi) && AbstractC7609s.f(this.obv, chartIndicatorSetting.obv) && AbstractC7609s.f(this.stochrsi, chartIndicatorSetting.stochrsi) && AbstractC7609s.f(this.trix, chartIndicatorSetting.trix) && AbstractC7609s.f(this.wr, chartIndicatorSetting.wr) && AbstractC7609s.f(this.cci, chartIndicatorSetting.cci) && AbstractC7609s.f(this.roc, chartIndicatorSetting.roc) && AbstractC7609s.f(this.atr, chartIndicatorSetting.atr) && AbstractC7609s.f(this.dmi, chartIndicatorSetting.dmi) && AbstractC7609s.f(this.vr, chartIndicatorSetting.vr) && AbstractC7609s.f(this.psy, chartIndicatorSetting.psy) && AbstractC7609s.f(this.bias, chartIndicatorSetting.bias) && AbstractC7609s.f(this.smi, chartIndicatorSetting.smi) && AbstractC7609s.f(this.skdj, chartIndicatorSetting.skdj) && AbstractC7609s.f(this.dma, chartIndicatorSetting.dma) && AbstractC7609s.f(this.mtm, chartIndicatorSetting.mtm) && AbstractC7609s.f(this.bbw, chartIndicatorSetting.bbw) && AbstractC7609s.f(this.fundflow, chartIndicatorSetting.fundflow) && AbstractC7609s.f(this.position, chartIndicatorSetting.position) && AbstractC7609s.f(this.ttsi, chartIndicatorSetting.ttsi) && AbstractC7609s.f(this.ttmu, chartIndicatorSetting.ttmu) && AbstractC7609s.f(this.brar, chartIndicatorSetting.brar) && AbstractC7609s.f(this.emv, chartIndicatorSetting.emv) && AbstractC7609s.f(this.mfi, chartIndicatorSetting.mfi) && AbstractC7609s.f(this.dpo, chartIndicatorSetting.dpo) && AbstractC7609s.f(this.ao, chartIndicatorSetting.ao) && AbstractC7609s.f(this.lsur, chartIndicatorSetting.lsur) && AbstractC7609s.f(this.basis, chartIndicatorSetting.basis) && AbstractC7609s.f(this.tvolume, chartIndicatorSetting.tvolume) && AbstractC7609s.f(this.ftbs, chartIndicatorSetting.ftbs) && AbstractC7609s.f(this.mlr, chartIndicatorSetting.mlr) && AbstractC7609s.f(this.bsv, chartIndicatorSetting.bsv) && AbstractC7609s.f(this.aifdi, chartIndicatorSetting.aifdi) && AbstractC7609s.f(this.aipd, chartIndicatorSetting.aipd) && AbstractC7609s.f(this.aili, chartIndicatorSetting.aili) && AbstractC7609s.f(this.aibsi, chartIndicatorSetting.aibsi) && AbstractC7609s.f(this.ainetvol, chartIndicatorSetting.ainetvol) && AbstractC7609s.f(this.aibst, chartIndicatorSetting.aibst) && AbstractC7609s.f(this.fr, chartIndicatorSetting.fr) && AbstractC7609s.f(this.pfr, chartIndicatorSetting.pfr) && AbstractC7609s.f(this.vpvr, chartIndicatorSetting.vpvr) && AbstractC7609s.f(this.liqheatmap, chartIndicatorSetting.liqheatmap);
    }

    public final AiAggtradeRemote getAiAggtrade() {
        return this.aiAggtrade;
    }

    public final AiBsiRemote getAibsi() {
        return this.aibsi;
    }

    public final AiBstRemote getAibst() {
        return this.aibst;
    }

    public final AiFDIRemote getAifdi() {
        return this.aifdi;
    }

    public final AiLIRemote getAili() {
        return this.aili;
    }

    public final AiNetVolRemote getAinetvol() {
        return this.ainetvol;
    }

    public final AiPDRemote getAipd() {
        return this.aipd;
    }

    public final AlligatorRemote getAlligator() {
        return this.alligator;
    }

    public final AORemote getAo() {
        return this.ao;
    }

    public final AtrRemote getAtr() {
        return this.atr;
    }

    public final BasisRemote getBasis() {
        return this.basis;
    }

    public final BBIRemote getBbi() {
        return this.bbi;
    }

    public final BbwRemote getBbw() {
        return this.bbw;
    }

    public final BiasRemote getBias() {
        return this.bias;
    }

    public final BollRemote getBoll() {
        return this.boll;
    }

    public final BRARRemote getBrar() {
        return this.brar;
    }

    public final BSVRemote getBsv() {
        return this.bsv;
    }

    public final CCIRemote getCci() {
        return this.cci;
    }

    public final DCRemote getDc() {
        return this.dc;
    }

    public final DmaRemote getDma() {
        return this.dma;
    }

    public final DmiRemote getDmi() {
        return this.dmi;
    }

    public final DPORemote getDpo() {
        return this.dpo;
    }

    public final EMARemote getEma() {
        return this.ema;
    }

    public final EMVRemote getEmv() {
        return this.emv;
    }

    public final ENERemote getEne() {
        return this.ene;
    }

    public final FRRemote getFr() {
        return this.fr;
    }

    public final FTBSRemote getFtbs() {
        return this.ftbs;
    }

    public final FundFlowRemote getFundflow() {
        return this.fundflow;
    }

    public final IchimokuRemote getIchimoku() {
        return this.ichimoku;
    }

    public final KCRemote getKc() {
        return this.kc;
    }

    public final KDJRemote getKdj() {
        return this.kdj;
    }

    public final LiqHeatmapRemote getLiqheatmap() {
        return this.liqheatmap;
    }

    public final LSURRemote getLsur() {
        return this.lsur;
    }

    public final MARemote getMa() {
        return this.ma;
    }

    public final MACDRemote getMacd() {
        return this.macd;
    }

    public final MFIRemote getMfi() {
        return this.mfi;
    }

    public final MLRRemote getMlr() {
        return this.mlr;
    }

    public final MtmRemote getMtm() {
        return this.mtm;
    }

    public final ObvRemote getObv() {
        return this.obv;
    }

    public final PFRRemote getPfr() {
        return this.pfr;
    }

    public final PositionRemote getPosition() {
        return this.position;
    }

    public final PsyRemote getPsy() {
        return this.psy;
    }

    public final ROCRemote getRoc() {
        return this.roc;
    }

    public final RsiRemote getRsi() {
        return this.rsi;
    }

    public final SARRemote getSar() {
        return this.sar;
    }

    public final SkdjRemote getSkdj() {
        return this.skdj;
    }

    public final SmiRemote getSmi() {
        return this.smi;
    }

    public final StochRSIRemote getStochrsi() {
        return this.stochrsi;
    }

    public final TDRemote getTd() {
        return this.td;
    }

    public final TrixRemote getTrix() {
        return this.trix;
    }

    public final TTMURemote getTtmu() {
        return this.ttmu;
    }

    public final TTSIRemote getTtsi() {
        return this.ttsi;
    }

    public final TVolumeRemote getTvolume() {
        return this.tvolume;
    }

    public final VolumeRemote getVolume() {
        return this.volume;
    }

    public final VPVRRemote getVpvr() {
        return this.vpvr;
    }

    public final VrRemote getVr() {
        return this.vr;
    }

    public final WRRemote getWr() {
        return this.wr;
    }

    public int hashCode() {
        BollRemote bollRemote = this.boll;
        int iHashCode = (bollRemote == null ? 0 : bollRemote.hashCode()) * 31;
        AiAggtradeRemote aiAggtradeRemote = this.aiAggtrade;
        int iHashCode2 = (iHashCode + (aiAggtradeRemote == null ? 0 : aiAggtradeRemote.hashCode())) * 31;
        DCRemote dCRemote = this.dc;
        int iHashCode3 = (iHashCode2 + (dCRemote == null ? 0 : dCRemote.hashCode())) * 31;
        ENERemote eNERemote = this.ene;
        int iHashCode4 = (iHashCode3 + (eNERemote == null ? 0 : eNERemote.hashCode())) * 31;
        IchimokuRemote ichimokuRemote = this.ichimoku;
        int iHashCode5 = (iHashCode4 + (ichimokuRemote == null ? 0 : ichimokuRemote.hashCode())) * 31;
        KCRemote kCRemote = this.kc;
        int iHashCode6 = (iHashCode5 + (kCRemote == null ? 0 : kCRemote.hashCode())) * 31;
        SARRemote sARRemote = this.sar;
        int iHashCode7 = (iHashCode6 + (sARRemote == null ? 0 : sARRemote.hashCode())) * 31;
        MARemote mARemote = this.ma;
        int iHashCode8 = (iHashCode7 + (mARemote == null ? 0 : mARemote.hashCode())) * 31;
        EMARemote eMARemote = this.ema;
        int iHashCode9 = (iHashCode8 + (eMARemote == null ? 0 : eMARemote.hashCode())) * 31;
        AlligatorRemote alligatorRemote = this.alligator;
        int iHashCode10 = (iHashCode9 + (alligatorRemote == null ? 0 : alligatorRemote.hashCode())) * 31;
        BBIRemote bBIRemote = this.bbi;
        int iHashCode11 = (iHashCode10 + (bBIRemote == null ? 0 : bBIRemote.hashCode())) * 31;
        TDRemote tDRemote = this.td;
        int iHashCode12 = (iHashCode11 + (tDRemote == null ? 0 : tDRemote.hashCode())) * 31;
        VolumeRemote volumeRemote = this.volume;
        int iHashCode13 = (iHashCode12 + (volumeRemote == null ? 0 : volumeRemote.hashCode())) * 31;
        MACDRemote mACDRemote = this.macd;
        int iHashCode14 = (iHashCode13 + (mACDRemote == null ? 0 : mACDRemote.hashCode())) * 31;
        KDJRemote kDJRemote = this.kdj;
        int iHashCode15 = (iHashCode14 + (kDJRemote == null ? 0 : kDJRemote.hashCode())) * 31;
        RsiRemote rsiRemote = this.rsi;
        int iHashCode16 = (iHashCode15 + (rsiRemote == null ? 0 : rsiRemote.hashCode())) * 31;
        ObvRemote obvRemote = this.obv;
        int iHashCode17 = (iHashCode16 + (obvRemote == null ? 0 : obvRemote.hashCode())) * 31;
        StochRSIRemote stochRSIRemote = this.stochrsi;
        int iHashCode18 = (iHashCode17 + (stochRSIRemote == null ? 0 : stochRSIRemote.hashCode())) * 31;
        TrixRemote trixRemote = this.trix;
        int iHashCode19 = (iHashCode18 + (trixRemote == null ? 0 : trixRemote.hashCode())) * 31;
        WRRemote wRRemote = this.wr;
        int iHashCode20 = (iHashCode19 + (wRRemote == null ? 0 : wRRemote.hashCode())) * 31;
        CCIRemote cCIRemote = this.cci;
        int iHashCode21 = (iHashCode20 + (cCIRemote == null ? 0 : cCIRemote.hashCode())) * 31;
        ROCRemote rOCRemote = this.roc;
        int iHashCode22 = (iHashCode21 + (rOCRemote == null ? 0 : rOCRemote.hashCode())) * 31;
        AtrRemote atrRemote = this.atr;
        int iHashCode23 = (iHashCode22 + (atrRemote == null ? 0 : atrRemote.hashCode())) * 31;
        DmiRemote dmiRemote = this.dmi;
        int iHashCode24 = (iHashCode23 + (dmiRemote == null ? 0 : dmiRemote.hashCode())) * 31;
        VrRemote vrRemote = this.vr;
        int iHashCode25 = (iHashCode24 + (vrRemote == null ? 0 : vrRemote.hashCode())) * 31;
        PsyRemote psyRemote = this.psy;
        int iHashCode26 = (iHashCode25 + (psyRemote == null ? 0 : psyRemote.hashCode())) * 31;
        BiasRemote biasRemote = this.bias;
        int iHashCode27 = (iHashCode26 + (biasRemote == null ? 0 : biasRemote.hashCode())) * 31;
        SmiRemote smiRemote = this.smi;
        int iHashCode28 = (iHashCode27 + (smiRemote == null ? 0 : smiRemote.hashCode())) * 31;
        SkdjRemote skdjRemote = this.skdj;
        int iHashCode29 = (iHashCode28 + (skdjRemote == null ? 0 : skdjRemote.hashCode())) * 31;
        DmaRemote dmaRemote = this.dma;
        int iHashCode30 = (iHashCode29 + (dmaRemote == null ? 0 : dmaRemote.hashCode())) * 31;
        MtmRemote mtmRemote = this.mtm;
        int iHashCode31 = (iHashCode30 + (mtmRemote == null ? 0 : mtmRemote.hashCode())) * 31;
        BbwRemote bbwRemote = this.bbw;
        int iHashCode32 = (iHashCode31 + (bbwRemote == null ? 0 : bbwRemote.hashCode())) * 31;
        FundFlowRemote fundFlowRemote = this.fundflow;
        int iHashCode33 = (iHashCode32 + (fundFlowRemote == null ? 0 : fundFlowRemote.hashCode())) * 31;
        PositionRemote positionRemote = this.position;
        int iHashCode34 = (iHashCode33 + (positionRemote == null ? 0 : positionRemote.hashCode())) * 31;
        TTSIRemote tTSIRemote = this.ttsi;
        int iHashCode35 = (iHashCode34 + (tTSIRemote == null ? 0 : tTSIRemote.hashCode())) * 31;
        TTMURemote tTMURemote = this.ttmu;
        int iHashCode36 = (iHashCode35 + (tTMURemote == null ? 0 : tTMURemote.hashCode())) * 31;
        BRARRemote bRARRemote = this.brar;
        int iHashCode37 = (iHashCode36 + (bRARRemote == null ? 0 : bRARRemote.hashCode())) * 31;
        EMVRemote eMVRemote = this.emv;
        int iHashCode38 = (iHashCode37 + (eMVRemote == null ? 0 : eMVRemote.hashCode())) * 31;
        MFIRemote mFIRemote = this.mfi;
        int iHashCode39 = (iHashCode38 + (mFIRemote == null ? 0 : mFIRemote.hashCode())) * 31;
        DPORemote dPORemote = this.dpo;
        int iHashCode40 = (iHashCode39 + (dPORemote == null ? 0 : dPORemote.hashCode())) * 31;
        AORemote aORemote = this.ao;
        int iHashCode41 = (iHashCode40 + (aORemote == null ? 0 : aORemote.hashCode())) * 31;
        LSURRemote lSURRemote = this.lsur;
        int iHashCode42 = (iHashCode41 + (lSURRemote == null ? 0 : lSURRemote.hashCode())) * 31;
        BasisRemote basisRemote = this.basis;
        int iHashCode43 = (iHashCode42 + (basisRemote == null ? 0 : basisRemote.hashCode())) * 31;
        TVolumeRemote tVolumeRemote = this.tvolume;
        int iHashCode44 = (iHashCode43 + (tVolumeRemote == null ? 0 : tVolumeRemote.hashCode())) * 31;
        FTBSRemote fTBSRemote = this.ftbs;
        int iHashCode45 = (iHashCode44 + (fTBSRemote == null ? 0 : fTBSRemote.hashCode())) * 31;
        MLRRemote mLRRemote = this.mlr;
        int iHashCode46 = (iHashCode45 + (mLRRemote == null ? 0 : mLRRemote.hashCode())) * 31;
        BSVRemote bSVRemote = this.bsv;
        int iHashCode47 = (iHashCode46 + (bSVRemote == null ? 0 : bSVRemote.hashCode())) * 31;
        AiFDIRemote aiFDIRemote = this.aifdi;
        int iHashCode48 = (iHashCode47 + (aiFDIRemote == null ? 0 : aiFDIRemote.hashCode())) * 31;
        AiPDRemote aiPDRemote = this.aipd;
        int iHashCode49 = (iHashCode48 + (aiPDRemote == null ? 0 : aiPDRemote.hashCode())) * 31;
        AiLIRemote aiLIRemote = this.aili;
        int iHashCode50 = (iHashCode49 + (aiLIRemote == null ? 0 : aiLIRemote.hashCode())) * 31;
        AiBsiRemote aiBsiRemote = this.aibsi;
        int iHashCode51 = (iHashCode50 + (aiBsiRemote == null ? 0 : aiBsiRemote.hashCode())) * 31;
        AiNetVolRemote aiNetVolRemote = this.ainetvol;
        int iHashCode52 = (iHashCode51 + (aiNetVolRemote == null ? 0 : aiNetVolRemote.hashCode())) * 31;
        AiBstRemote aiBstRemote = this.aibst;
        int iHashCode53 = (iHashCode52 + (aiBstRemote == null ? 0 : aiBstRemote.hashCode())) * 31;
        FRRemote fRRemote = this.fr;
        int iHashCode54 = (iHashCode53 + (fRRemote == null ? 0 : fRRemote.hashCode())) * 31;
        PFRRemote pFRRemote = this.pfr;
        int iHashCode55 = (iHashCode54 + (pFRRemote == null ? 0 : pFRRemote.hashCode())) * 31;
        VPVRRemote vPVRRemote = this.vpvr;
        int iHashCode56 = (iHashCode55 + (vPVRRemote == null ? 0 : vPVRRemote.hashCode())) * 31;
        LiqHeatmapRemote liqHeatmapRemote = this.liqheatmap;
        return iHashCode56 + (liqHeatmapRemote != null ? liqHeatmapRemote.hashCode() : 0);
    }

    public String toString() {
        return "ChartIndicatorSetting(boll=" + this.boll + ", aiAggtrade=" + this.aiAggtrade + ", dc=" + this.dc + ", ene=" + this.ene + ", ichimoku=" + this.ichimoku + ", kc=" + this.kc + ", sar=" + this.sar + ", ma=" + this.ma + ", ema=" + this.ema + ", alligator=" + this.alligator + ", bbi=" + this.bbi + ", td=" + this.td + ", volume=" + this.volume + ", macd=" + this.macd + ", kdj=" + this.kdj + ", rsi=" + this.rsi + ", obv=" + this.obv + ", stochrsi=" + this.stochrsi + ", trix=" + this.trix + ", wr=" + this.wr + ", cci=" + this.cci + ", roc=" + this.roc + ", atr=" + this.atr + ", dmi=" + this.dmi + ", vr=" + this.vr + ", psy=" + this.psy + ", bias=" + this.bias + ", smi=" + this.smi + ", skdj=" + this.skdj + ", dma=" + this.dma + ", mtm=" + this.mtm + ", bbw=" + this.bbw + ", fundflow=" + this.fundflow + ", position=" + this.position + ", ttsi=" + this.ttsi + ", ttmu=" + this.ttmu + ", brar=" + this.brar + ", emv=" + this.emv + ", mfi=" + this.mfi + ", dpo=" + this.dpo + ", ao=" + this.ao + ", lsur=" + this.lsur + ", basis=" + this.basis + ", tvolume=" + this.tvolume + ", ftbs=" + this.ftbs + ", mlr=" + this.mlr + ", bsv=" + this.bsv + ", aifdi=" + this.aifdi + ", aipd=" + this.aipd + ", aili=" + this.aili + ", aibsi=" + this.aibsi + ", ainetvol=" + this.ainetvol + ", aibst=" + this.aibst + ", fr=" + this.fr + ", pfr=" + this.pfr + ", vpvr=" + this.vpvr + ", liqheatmap=" + this.liqheatmap + ')';
    }
}
