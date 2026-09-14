package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.alibaba.sdk.android.tbrest.rest.RestUrlWrapper;
import com.tencent.wcdb.database.SQLiteDatabase;
import com.tencent.wcdb.database.SQLiteGlobal;
import com.umeng.analytics.pro.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import okhttp3.internal.http2.Http2Connection;
import p167hg.AbstractC7609s;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00003\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\b\n\u0002\u0010\u0006\n\u0002\b\u0015\n\u0002\u0010\t\n\u0003\b·\u0001\n\u0002\u0010\u000b\n\u0002\b\u0004\b\u0087\b\u0018\u00002\u00020\u0001Bë\u0004\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u000f\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u000f\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u000f\u0012\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0017\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u000f\u0012\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u001a\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u001b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u001c\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u001d\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u001e\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u001f\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010 \u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010!\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\"\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010#\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010$\u001a\u0004\u0018\u00010%\u0012\n\b\u0002\u0010&\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010'\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010(\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010)\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010*\u001a\u0004\u0018\u00010%\u0012\n\b\u0002\u0010+\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0002\u0010,\u001a\u0004\u0018\u00010%\u0012\n\b\u0002\u0010-\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010.\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010/\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00100\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00101\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00102\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00103\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00104\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00105\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00106\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00107\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u00108\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b9\u0010:J\f\u0010§\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010¨\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010©\u0001\u001a\u0004\u0018\u00010\u0006HÆ\u0003¢\u0006\u0002\u0010BJ\f\u0010ª\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010«\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010¬\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010\u00ad\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010®\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010¯\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010°\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010±\u0001\u001a\u0004\u0018\u00010\u000fHÆ\u0003¢\u0006\u0002\u0010UJ\f\u0010²\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010³\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010´\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010µ\u0001\u001a\u0004\u0018\u00010\u000fHÆ\u0003¢\u0006\u0002\u0010UJ\f\u0010¶\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010·\u0001\u001a\u0004\u0018\u00010\u000fHÆ\u0003¢\u0006\u0002\u0010UJ\f\u0010¸\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010¹\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010º\u0001\u001a\u0004\u0018\u00010\u000fHÆ\u0003¢\u0006\u0002\u0010UJ\f\u0010»\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010¼\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010½\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010¾\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010¿\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010À\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Á\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Â\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ã\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ä\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Å\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0012\u0010Æ\u0001\u001a\u0004\u0018\u00010%HÆ\u0003¢\u0006\u0003\u0010\u0082\u0001J\f\u0010Ç\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010È\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010É\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ê\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0012\u0010Ë\u0001\u001a\u0004\u0018\u00010%HÆ\u0003¢\u0006\u0003\u0010\u0082\u0001J\u0011\u0010Ì\u0001\u001a\u0004\u0018\u00010\u0006HÆ\u0003¢\u0006\u0002\u0010BJ\u0012\u0010Í\u0001\u001a\u0004\u0018\u00010%HÆ\u0003¢\u0006\u0003\u0010\u0082\u0001J\f\u0010Î\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ï\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ð\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ñ\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ò\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ó\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ô\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Õ\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ö\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010×\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ø\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\f\u0010Ù\u0001\u001a\u0004\u0018\u00010\u0003HÆ\u0003Jô\u0004\u0010Ú\u0001\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u00062\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u000f2\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u000f2\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u000f2\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0017\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u000f2\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001a\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001c\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001d\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u001f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010 \u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010!\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\"\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010#\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010$\u001a\u0004\u0018\u00010%2\n\b\u0002\u0010&\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010'\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010(\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010)\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010*\u001a\u0004\u0018\u00010%2\n\b\u0002\u0010+\u001a\u0004\u0018\u00010\u00062\n\b\u0002\u0010,\u001a\u0004\u0018\u00010%2\n\b\u0002\u0010-\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010.\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010/\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00100\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00101\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00102\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00103\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00104\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00105\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00106\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00107\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u00108\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0003\u0010Û\u0001J\u0016\u0010Ü\u0001\u001a\u00030Ý\u00012\t\u0010Þ\u0001\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\n\u0010ß\u0001\u001a\u00020\u0006HÖ\u0001J\n\u0010à\u0001\u001a\u00020\u0003HÖ\u0001R\u001c\u0010\u0002\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b;\u0010<\"\u0004\b=\u0010>R\u001c\u0010\u0004\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b?\u0010<\"\u0004\b@\u0010>R\u001e\u0010\u0005\u001a\u0004\u0018\u00010\u0006X\u0086\u000e¢\u0006\u0010\n\u0002\u0010E\u001a\u0004\bA\u0010B\"\u0004\bC\u0010DR\u001c\u0010\u0007\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bF\u0010<\"\u0004\bG\u0010>R\u001c\u0010\b\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bH\u0010<\"\u0004\bI\u0010>R\u001c\u0010\t\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bJ\u0010<\"\u0004\bK\u0010>R\u001c\u0010\n\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bL\u0010<\"\u0004\bM\u0010>R\u001c\u0010\u000b\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bN\u0010<\"\u0004\bO\u0010>R\u001c\u0010\f\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bP\u0010<\"\u0004\bQ\u0010>R\u001c\u0010\r\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bR\u0010<\"\u0004\bS\u0010>R\u001e\u0010\u000e\u001a\u0004\u0018\u00010\u000fX\u0086\u000e¢\u0006\u0010\n\u0002\u0010X\u001a\u0004\bT\u0010U\"\u0004\bV\u0010WR\u001c\u0010\u0010\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bY\u0010<\"\u0004\bZ\u0010>R\u001c\u0010\u0011\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b[\u0010<\"\u0004\b\\\u0010>R\u001c\u0010\u0012\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b]\u0010<\"\u0004\b^\u0010>R\u001e\u0010\u0013\u001a\u0004\u0018\u00010\u000fX\u0086\u000e¢\u0006\u0010\n\u0002\u0010X\u001a\u0004\b_\u0010U\"\u0004\b`\u0010WR\u001c\u0010\u0014\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\ba\u0010<\"\u0004\bb\u0010>R\u001e\u0010\u0015\u001a\u0004\u0018\u00010\u000fX\u0086\u000e¢\u0006\u0010\n\u0002\u0010X\u001a\u0004\bc\u0010U\"\u0004\bd\u0010WR\u001c\u0010\u0016\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\be\u0010<\"\u0004\bf\u0010>R\u001c\u0010\u0017\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bg\u0010<\"\u0004\bh\u0010>R\u001e\u0010\u0018\u001a\u0004\u0018\u00010\u000fX\u0086\u000e¢\u0006\u0010\n\u0002\u0010X\u001a\u0004\bi\u0010U\"\u0004\bj\u0010WR\u001c\u0010\u0019\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bk\u0010<\"\u0004\bl\u0010>R\u001c\u0010\u001a\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bm\u0010<\"\u0004\bn\u0010>R\u001c\u0010\u001b\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bo\u0010<\"\u0004\bp\u0010>R\u001c\u0010\u001c\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bq\u0010<\"\u0004\br\u0010>R\u001c\u0010\u001d\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bs\u0010<\"\u0004\bt\u0010>R\u001c\u0010\u001e\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bu\u0010<\"\u0004\bv\u0010>R\u001c\u0010\u001f\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\bw\u0010<\"\u0004\bx\u0010>R\u001c\u0010 \u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\by\u0010<\"\u0004\bz\u0010>R\u001c\u0010!\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b{\u0010<\"\u0004\b|\u0010>R\u001c\u0010\"\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b}\u0010<\"\u0004\b~\u0010>R\u001d\u0010#\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000f\n\u0000\u001a\u0004\b\u007f\u0010<\"\u0005\b\u0080\u0001\u0010>R#\u0010$\u001a\u0004\u0018\u00010%X\u0086\u000e¢\u0006\u0015\n\u0003\u0010\u0085\u0001\u001a\u0006\b\u0081\u0001\u0010\u0082\u0001\"\u0006\b\u0083\u0001\u0010\u0084\u0001R\u001e\u0010&\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u0086\u0001\u0010<\"\u0005\b\u0087\u0001\u0010>R\u001e\u0010'\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u0088\u0001\u0010<\"\u0005\b\u0089\u0001\u0010>R\u001e\u0010(\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u008a\u0001\u0010<\"\u0005\b\u008b\u0001\u0010>R\u001e\u0010)\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u008c\u0001\u0010<\"\u0005\b\u008d\u0001\u0010>R#\u0010*\u001a\u0004\u0018\u00010%X\u0086\u000e¢\u0006\u0015\n\u0003\u0010\u0085\u0001\u001a\u0006\b\u008e\u0001\u0010\u0082\u0001\"\u0006\b\u008f\u0001\u0010\u0084\u0001R \u0010+\u001a\u0004\u0018\u00010\u0006X\u0086\u000e¢\u0006\u0012\n\u0002\u0010E\u001a\u0005\b\u0090\u0001\u0010B\"\u0005\b\u0091\u0001\u0010DR#\u0010,\u001a\u0004\u0018\u00010%X\u0086\u000e¢\u0006\u0015\n\u0003\u0010\u0085\u0001\u001a\u0006\b\u0092\u0001\u0010\u0082\u0001\"\u0006\b\u0093\u0001\u0010\u0084\u0001R\u001e\u0010-\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u0094\u0001\u0010<\"\u0005\b\u0095\u0001\u0010>R\u0014\u0010.\u001a\u0004\u0018\u00010\u0003¢\u0006\t\n\u0000\u001a\u0005\b\u0096\u0001\u0010<R\u0014\u0010/\u001a\u0004\u0018\u00010\u0003¢\u0006\t\n\u0000\u001a\u0005\b\u0097\u0001\u0010<R\u0014\u00100\u001a\u0004\u0018\u00010\u0003¢\u0006\t\n\u0000\u001a\u0005\b\u0098\u0001\u0010<R\u0014\u00101\u001a\u0004\u0018\u00010\u0003¢\u0006\t\n\u0000\u001a\u0005\b\u0099\u0001\u0010<R\u0014\u00102\u001a\u0004\u0018\u00010\u0003¢\u0006\t\n\u0000\u001a\u0005\b\u009a\u0001\u0010<R\u001e\u00103\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u009b\u0001\u0010<\"\u0005\b\u009c\u0001\u0010>R\u001e\u00104\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u009d\u0001\u0010<\"\u0005\b\u009e\u0001\u0010>R\u001e\u00105\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b\u009f\u0001\u0010<\"\u0005\b \u0001\u0010>R\u001e\u00106\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b¡\u0001\u0010<\"\u0005\b¢\u0001\u0010>R\u001e\u00107\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b£\u0001\u0010<\"\u0005\b¤\u0001\u0010>R\u001e\u00108\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0000\u001a\u0005\b¥\u0001\u0010<\"\u0005\b¦\u0001\u0010>¨\u0006á\u0001"}, d2 = {"Lsp/aicoin_kline/chart/data/LargeOrderItem;", "", "last_vol", "", "depth_state", "depth_state_int", "", "high_vol", "coin_type", "uptrade_time", "uporder_time", RestUrlWrapper.FIELD_PLATFORM, d.f89985p, "depth_amount", "depth_amount_double", "", "depth_vol", "depth_status", "fake_price", "fake_price_double", "depth_price", "depth_price_double", "depth_type", "trade_amount", "trade_amount_double", "trade_type", "trade_vol", "trade_count", "trade_price", "high_trade_amount", "show_state", "id", "high_amount", "last_amount", "coin", "miss_time", "miss_time_long", "", "hold_time", "miss_price", "trade_miss_price", "order_miss_price", "draw_start_time", "draw_start_time_index", "draw_miss_time", "rate", "trade_turnover", "depth_turnover", "high_trade_turnover", "last_turnover", "position_sub", "filter_state", "market_logo", SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_MARKET_NAME, "orderdownBound", "completedownBound", "position_sub_turnover", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Long;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Long;Ljava/lang/Integer;Ljava/lang/Long;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getLast_vol", "()Ljava/lang/String;", "setLast_vol", "(Ljava/lang/String;)V", "getDepth_state", "setDepth_state", "getDepth_state_int", "()Ljava/lang/Integer;", "setDepth_state_int", "(Ljava/lang/Integer;)V", "Ljava/lang/Integer;", "getHigh_vol", "setHigh_vol", "getCoin_type", "setCoin_type", "getUptrade_time", "setUptrade_time", "getUporder_time", "setUporder_time", "getPlatform", "setPlatform", "getStart_time", "setStart_time", "getDepth_amount", "setDepth_amount", "getDepth_amount_double", "()Ljava/lang/Double;", "setDepth_amount_double", "(Ljava/lang/Double;)V", "Ljava/lang/Double;", "getDepth_vol", "setDepth_vol", "getDepth_status", "setDepth_status", "getFake_price", "setFake_price", "getFake_price_double", "setFake_price_double", "getDepth_price", "setDepth_price", "getDepth_price_double", "setDepth_price_double", "getDepth_type", "setDepth_type", "getTrade_amount", "setTrade_amount", "getTrade_amount_double", "setTrade_amount_double", "getTrade_type", "setTrade_type", "getTrade_vol", "setTrade_vol", "getTrade_count", "setTrade_count", "getTrade_price", "setTrade_price", "getHigh_trade_amount", "setHigh_trade_amount", "getShow_state", "setShow_state", "getId", "setId", "getHigh_amount", "setHigh_amount", "getLast_amount", "setLast_amount", "getCoin", "setCoin", "getMiss_time", "setMiss_time", "getMiss_time_long", "()Ljava/lang/Long;", "setMiss_time_long", "(Ljava/lang/Long;)V", "Ljava/lang/Long;", "getHold_time", "setHold_time", "getMiss_price", "setMiss_price", "getTrade_miss_price", "setTrade_miss_price", "getOrder_miss_price", "setOrder_miss_price", "getDraw_start_time", "setDraw_start_time", "getDraw_start_time_index", "setDraw_start_time_index", "getDraw_miss_time", "setDraw_miss_time", "getRate", "setRate", "getTrade_turnover", "getDepth_turnover", "getHigh_trade_turnover", "getLast_turnover", "getPosition_sub", "getFilter_state", "setFilter_state", "getMarket_logo", "setMarket_logo", "getMarket_name", "setMarket_name", "getOrderdownBound", "setOrderdownBound", "getCompletedownBound", "setCompletedownBound", "getPosition_sub_turnover", "setPosition_sub_turnover", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component19", "component20", "component21", "component22", "component23", "component24", "component25", "component26", "component27", "component28", "component29", "component30", "component31", "component32", "component33", "component34", "component35", "component36", "component37", "component38", "component39", "component40", "component41", "component42", "component43", "component44", "component45", "component46", "component47", "component48", "component49", "component50", "component51", "copy", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Long;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Long;Ljava/lang/Integer;Ljava/lang/Long;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Lsp/aicoin_kline/chart/data/LargeOrderItem;", "equals", "", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LargeOrderItem {
    private String coin;
    private String coin_type;
    private String completedownBound;
    private String depth_amount;
    private Double depth_amount_double;
    private String depth_price;
    private Double depth_price_double;
    private String depth_state;
    private Integer depth_state_int;
    private String depth_status;
    private final String depth_turnover;
    private String depth_type;
    private String depth_vol;
    private Long draw_miss_time;
    private Long draw_start_time;
    private Integer draw_start_time_index;
    private String fake_price;
    private Double fake_price_double;
    private String filter_state;
    private String high_amount;
    private String high_trade_amount;
    private final String high_trade_turnover;
    private String high_vol;
    private String hold_time;
    private String id;
    private String last_amount;
    private final String last_turnover;
    private String last_vol;
    private String market_logo;
    private String market_name;
    private String miss_price;
    private String miss_time;
    private Long miss_time_long;
    private String order_miss_price;
    private String orderdownBound;
    private String platform;
    private final String position_sub;
    private String position_sub_turnover;
    private String rate;
    private String show_state;
    private String start_time;
    private String trade_amount;
    private Double trade_amount_double;
    private String trade_count;
    private String trade_miss_price;
    private String trade_price;
    private final String trade_turnover;
    private String trade_type;
    private String trade_vol;
    private String uporder_time;
    private String uptrade_time;

    public LargeOrderItem() {
        this(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 524287, null);
    }

    public LargeOrderItem(String str, String str2, Integer num, String str3, String str4, String str5, String str6, String str7, String str8, String str9, Double d10, String str10, String str11, String str12, Double d11, String str13, Double d12, String str14, String str15, Double d13, String str16, String str17, String str18, String str19, String str20, String str21, String str22, String str23, String str24, String str25, String str26, Long l10, String str27, String str28, String str29, String str30, Long l11, Integer num2, Long l12, String str31, String str32, String str33, String str34, String str35, String str36, String str37, String str38, String str39, String str40, String str41, String str42) {
        this.last_vol = str;
        this.depth_state = str2;
        this.depth_state_int = num;
        this.high_vol = str3;
        this.coin_type = str4;
        this.uptrade_time = str5;
        this.uporder_time = str6;
        this.platform = str7;
        this.start_time = str8;
        this.depth_amount = str9;
        this.depth_amount_double = d10;
        this.depth_vol = str10;
        this.depth_status = str11;
        this.fake_price = str12;
        this.fake_price_double = d11;
        this.depth_price = str13;
        this.depth_price_double = d12;
        this.depth_type = str14;
        this.trade_amount = str15;
        this.trade_amount_double = d13;
        this.trade_type = str16;
        this.trade_vol = str17;
        this.trade_count = str18;
        this.trade_price = str19;
        this.high_trade_amount = str20;
        this.show_state = str21;
        this.id = str22;
        this.high_amount = str23;
        this.last_amount = str24;
        this.coin = str25;
        this.miss_time = str26;
        this.miss_time_long = l10;
        this.hold_time = str27;
        this.miss_price = str28;
        this.trade_miss_price = str29;
        this.order_miss_price = str30;
        this.draw_start_time = l11;
        this.draw_start_time_index = num2;
        this.draw_miss_time = l12;
        this.rate = str31;
        this.trade_turnover = str32;
        this.depth_turnover = str33;
        this.high_trade_turnover = str34;
        this.last_turnover = str35;
        this.position_sub = str36;
        this.filter_state = str37;
        this.market_logo = str38;
        this.market_name = str39;
        this.orderdownBound = str40;
        this.completedownBound = str41;
        this.position_sub_turnover = str42;
    }

    /* JADX WARN: Illegal instructions before constructor call */
    public /* synthetic */ LargeOrderItem(String str, String str2, Integer num, String str3, String str4, String str5, String str6, String str7, String str8, String str9, Double d10, String str10, String str11, String str12, Double d11, String str13, Double d12, String str14, String str15, Double d13, String str16, String str17, String str18, String str19, String str20, String str21, String str22, String str23, String str24, String str25, String str26, Long l10, String str27, String str28, String str29, String str30, Long l11, Integer num2, Long l12, String str31, String str32, String str33, String str34, String str35, String str36, String str37, String str38, String str39, String str40, String str41, String str42, int i10, int i11, DefaultConstructorMarker defaultConstructorMarker) {
        String str43 = (i10 & 1) != 0 ? "0.0" : str;
        this(str43, (i10 & 2) != 0 ? "0" : str2, (i10 & 4) != 0 ? 0 : num, (i10 & 8) != 0 ? "0.0" : str3, (i10 & 16) != 0 ? "" : str4, (i10 & 32) != 0 ? "0L" : str5, (i10 & 64) != 0 ? "0L" : str6, (i10 & 128) != 0 ? "" : str7, (i10 & 256) != 0 ? "0L" : str8, (i10 & 512) != 0 ? "0.0" : str9, (i10 & 1024) != 0 ? Double.valueOf(0.0d) : d10, (i10 & 2048) != 0 ? "0.0" : str10, (i10 & 4096) != 0 ? "0" : str11, (i10 & 8192) != 0 ? "0.0" : str12, (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? Double.valueOf(0.0d) : d11, (i10 & 32768) != 0 ? "0.0" : str13, (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? Double.valueOf(0.0d) : d12, (i10 & 131072) != 0 ? "" : str14, (i10 & 262144) != 0 ? "0.0" : str15, (i10 & SQLiteGlobal.journalSizeLimit) != 0 ? Double.valueOf(0.0d) : d13, (i10 & 1048576) != 0 ? "" : str16, (i10 & 2097152) != 0 ? "0.0" : str17, (i10 & 4194304) != 0 ? "0.0" : str18, (i10 & 8388608) != 0 ? "0.0" : str19, (i10 & Http2Connection.OKHTTP_CLIENT_WINDOW_SIZE) != 0 ? "0.0" : str20, (i10 & 33554432) != 0 ? "0" : str21, (i10 & 67108864) != 0 ? "" : str22, (i10 & 134217728) != 0 ? "0.0" : str23, (i10 & 268435456) != 0 ? "0.0" : str24, (i10 & SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING) != 0 ? "" : str25, (i10 & 1073741824) != 0 ? "0L" : str26, (i10 & Integer.MIN_VALUE) != 0 ? 0L : l10, (i11 & 1) == 0 ? str27 : "0L", (i11 & 2) != 0 ? "0.0" : str28, (i11 & 4) != 0 ? "0.0" : str29, (i11 & 8) != 0 ? "0.0" : str30, (i11 & 16) != 0 ? 0L : l11, (i11 & 32) != 0 ? 0 : num2, (i11 & 64) != 0 ? 0L : l12, (i11 & 128) != 0 ? "0.0" : str31, (i11 & 256) != 0 ? "0.0" : str32, (i11 & 512) != 0 ? "0.0" : str33, (i11 & 1024) != 0 ? "0.0" : str34, (i11 & 2048) != 0 ? "0.0" : str35, (i11 & 4096) == 0 ? str36 : "0.0", (i11 & 8192) == 0 ? str37 : "0", (i11 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? "" : str38, (i11 & 32768) != 0 ? "" : str39, (i11 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? "" : str40, (i11 & 131072) != 0 ? "" : str41, (i11 & 262144) != 0 ? "" : str42);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getLast_vol() {
        return this.last_vol;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getDepth_amount() {
        return this.depth_amount;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final Double getDepth_amount_double() {
        return this.depth_amount_double;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getDepth_vol() {
        return this.depth_vol;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getDepth_status() {
        return this.depth_status;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final String getFake_price() {
        return this.fake_price;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final Double getFake_price_double() {
        return this.fake_price_double;
    }

    /* JADX INFO: renamed from: component16, reason: from getter */
    public final String getDepth_price() {
        return this.depth_price;
    }

    /* JADX INFO: renamed from: component17, reason: from getter */
    public final Double getDepth_price_double() {
        return this.depth_price_double;
    }

    /* JADX INFO: renamed from: component18, reason: from getter */
    public final String getDepth_type() {
        return this.depth_type;
    }

    /* JADX INFO: renamed from: component19, reason: from getter */
    public final String getTrade_amount() {
        return this.trade_amount;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getDepth_state() {
        return this.depth_state;
    }

    /* JADX INFO: renamed from: component20, reason: from getter */
    public final Double getTrade_amount_double() {
        return this.trade_amount_double;
    }

    /* JADX INFO: renamed from: component21, reason: from getter */
    public final String getTrade_type() {
        return this.trade_type;
    }

    /* JADX INFO: renamed from: component22, reason: from getter */
    public final String getTrade_vol() {
        return this.trade_vol;
    }

    /* JADX INFO: renamed from: component23, reason: from getter */
    public final String getTrade_count() {
        return this.trade_count;
    }

    /* JADX INFO: renamed from: component24, reason: from getter */
    public final String getTrade_price() {
        return this.trade_price;
    }

    /* JADX INFO: renamed from: component25, reason: from getter */
    public final String getHigh_trade_amount() {
        return this.high_trade_amount;
    }

    /* JADX INFO: renamed from: component26, reason: from getter */
    public final String getShow_state() {
        return this.show_state;
    }

    /* JADX INFO: renamed from: component27, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component28, reason: from getter */
    public final String getHigh_amount() {
        return this.high_amount;
    }

    /* JADX INFO: renamed from: component29, reason: from getter */
    public final String getLast_amount() {
        return this.last_amount;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final Integer getDepth_state_int() {
        return this.depth_state_int;
    }

    /* JADX INFO: renamed from: component30, reason: from getter */
    public final String getCoin() {
        return this.coin;
    }

    /* JADX INFO: renamed from: component31, reason: from getter */
    public final String getMiss_time() {
        return this.miss_time;
    }

    /* JADX INFO: renamed from: component32, reason: from getter */
    public final Long getMiss_time_long() {
        return this.miss_time_long;
    }

    /* JADX INFO: renamed from: component33, reason: from getter */
    public final String getHold_time() {
        return this.hold_time;
    }

    /* JADX INFO: renamed from: component34, reason: from getter */
    public final String getMiss_price() {
        return this.miss_price;
    }

    /* JADX INFO: renamed from: component35, reason: from getter */
    public final String getTrade_miss_price() {
        return this.trade_miss_price;
    }

    /* JADX INFO: renamed from: component36, reason: from getter */
    public final String getOrder_miss_price() {
        return this.order_miss_price;
    }

    /* JADX INFO: renamed from: component37, reason: from getter */
    public final Long getDraw_start_time() {
        return this.draw_start_time;
    }

    /* JADX INFO: renamed from: component38, reason: from getter */
    public final Integer getDraw_start_time_index() {
        return this.draw_start_time_index;
    }

    /* JADX INFO: renamed from: component39, reason: from getter */
    public final Long getDraw_miss_time() {
        return this.draw_miss_time;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getHigh_vol() {
        return this.high_vol;
    }

    /* JADX INFO: renamed from: component40, reason: from getter */
    public final String getRate() {
        return this.rate;
    }

    /* JADX INFO: renamed from: component41, reason: from getter */
    public final String getTrade_turnover() {
        return this.trade_turnover;
    }

    /* JADX INFO: renamed from: component42, reason: from getter */
    public final String getDepth_turnover() {
        return this.depth_turnover;
    }

    /* JADX INFO: renamed from: component43, reason: from getter */
    public final String getHigh_trade_turnover() {
        return this.high_trade_turnover;
    }

    /* JADX INFO: renamed from: component44, reason: from getter */
    public final String getLast_turnover() {
        return this.last_turnover;
    }

    /* JADX INFO: renamed from: component45, reason: from getter */
    public final String getPosition_sub() {
        return this.position_sub;
    }

    /* JADX INFO: renamed from: component46, reason: from getter */
    public final String getFilter_state() {
        return this.filter_state;
    }

    /* JADX INFO: renamed from: component47, reason: from getter */
    public final String getMarket_logo() {
        return this.market_logo;
    }

    /* JADX INFO: renamed from: component48, reason: from getter */
    public final String getMarket_name() {
        return this.market_name;
    }

    /* JADX INFO: renamed from: component49, reason: from getter */
    public final String getOrderdownBound() {
        return this.orderdownBound;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getCoin_type() {
        return this.coin_type;
    }

    /* JADX INFO: renamed from: component50, reason: from getter */
    public final String getCompletedownBound() {
        return this.completedownBound;
    }

    /* JADX INFO: renamed from: component51, reason: from getter */
    public final String getPosition_sub_turnover() {
        return this.position_sub_turnover;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getUptrade_time() {
        return this.uptrade_time;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getUporder_time() {
        return this.uporder_time;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getPlatform() {
        return this.platform;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getStart_time() {
        return this.start_time;
    }

    public final LargeOrderItem copy(String last_vol, String depth_state, Integer depth_state_int, String high_vol, String coin_type, String uptrade_time, String uporder_time, String platform, String start_time, String depth_amount, Double depth_amount_double, String depth_vol, String depth_status, String fake_price, Double fake_price_double, String depth_price, Double depth_price_double, String depth_type, String trade_amount, Double trade_amount_double, String trade_type, String trade_vol, String trade_count, String trade_price, String high_trade_amount, String show_state, String id2, String high_amount, String last_amount, String coin, String miss_time, Long miss_time_long, String hold_time, String miss_price, String trade_miss_price, String order_miss_price, Long draw_start_time, Integer draw_start_time_index, Long draw_miss_time, String rate, String trade_turnover, String depth_turnover, String high_trade_turnover, String last_turnover, String position_sub, String filter_state, String market_logo, String market_name, String orderdownBound, String completedownBound, String position_sub_turnover) {
        return new LargeOrderItem(last_vol, depth_state, depth_state_int, high_vol, coin_type, uptrade_time, uporder_time, platform, start_time, depth_amount, depth_amount_double, depth_vol, depth_status, fake_price, fake_price_double, depth_price, depth_price_double, depth_type, trade_amount, trade_amount_double, trade_type, trade_vol, trade_count, trade_price, high_trade_amount, show_state, id2, high_amount, last_amount, coin, miss_time, miss_time_long, hold_time, miss_price, trade_miss_price, order_miss_price, draw_start_time, draw_start_time_index, draw_miss_time, rate, trade_turnover, depth_turnover, high_trade_turnover, last_turnover, position_sub, filter_state, market_logo, market_name, orderdownBound, completedownBound, position_sub_turnover);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LargeOrderItem)) {
            return false;
        }
        LargeOrderItem largeOrderItem = (LargeOrderItem) other;
        return AbstractC7609s.f(this.last_vol, largeOrderItem.last_vol) && AbstractC7609s.f(this.depth_state, largeOrderItem.depth_state) && AbstractC7609s.f(this.depth_state_int, largeOrderItem.depth_state_int) && AbstractC7609s.f(this.high_vol, largeOrderItem.high_vol) && AbstractC7609s.f(this.coin_type, largeOrderItem.coin_type) && AbstractC7609s.f(this.uptrade_time, largeOrderItem.uptrade_time) && AbstractC7609s.f(this.uporder_time, largeOrderItem.uporder_time) && AbstractC7609s.f(this.platform, largeOrderItem.platform) && AbstractC7609s.f(this.start_time, largeOrderItem.start_time) && AbstractC7609s.f(this.depth_amount, largeOrderItem.depth_amount) && AbstractC7609s.f(this.depth_amount_double, largeOrderItem.depth_amount_double) && AbstractC7609s.f(this.depth_vol, largeOrderItem.depth_vol) && AbstractC7609s.f(this.depth_status, largeOrderItem.depth_status) && AbstractC7609s.f(this.fake_price, largeOrderItem.fake_price) && AbstractC7609s.f(this.fake_price_double, largeOrderItem.fake_price_double) && AbstractC7609s.f(this.depth_price, largeOrderItem.depth_price) && AbstractC7609s.f(this.depth_price_double, largeOrderItem.depth_price_double) && AbstractC7609s.f(this.depth_type, largeOrderItem.depth_type) && AbstractC7609s.f(this.trade_amount, largeOrderItem.trade_amount) && AbstractC7609s.f(this.trade_amount_double, largeOrderItem.trade_amount_double) && AbstractC7609s.f(this.trade_type, largeOrderItem.trade_type) && AbstractC7609s.f(this.trade_vol, largeOrderItem.trade_vol) && AbstractC7609s.f(this.trade_count, largeOrderItem.trade_count) && AbstractC7609s.f(this.trade_price, largeOrderItem.trade_price) && AbstractC7609s.f(this.high_trade_amount, largeOrderItem.high_trade_amount) && AbstractC7609s.f(this.show_state, largeOrderItem.show_state) && AbstractC7609s.f(this.id, largeOrderItem.id) && AbstractC7609s.f(this.high_amount, largeOrderItem.high_amount) && AbstractC7609s.f(this.last_amount, largeOrderItem.last_amount) && AbstractC7609s.f(this.coin, largeOrderItem.coin) && AbstractC7609s.f(this.miss_time, largeOrderItem.miss_time) && AbstractC7609s.f(this.miss_time_long, largeOrderItem.miss_time_long) && AbstractC7609s.f(this.hold_time, largeOrderItem.hold_time) && AbstractC7609s.f(this.miss_price, largeOrderItem.miss_price) && AbstractC7609s.f(this.trade_miss_price, largeOrderItem.trade_miss_price) && AbstractC7609s.f(this.order_miss_price, largeOrderItem.order_miss_price) && AbstractC7609s.f(this.draw_start_time, largeOrderItem.draw_start_time) && AbstractC7609s.f(this.draw_start_time_index, largeOrderItem.draw_start_time_index) && AbstractC7609s.f(this.draw_miss_time, largeOrderItem.draw_miss_time) && AbstractC7609s.f(this.rate, largeOrderItem.rate) && AbstractC7609s.f(this.trade_turnover, largeOrderItem.trade_turnover) && AbstractC7609s.f(this.depth_turnover, largeOrderItem.depth_turnover) && AbstractC7609s.f(this.high_trade_turnover, largeOrderItem.high_trade_turnover) && AbstractC7609s.f(this.last_turnover, largeOrderItem.last_turnover) && AbstractC7609s.f(this.position_sub, largeOrderItem.position_sub) && AbstractC7609s.f(this.filter_state, largeOrderItem.filter_state) && AbstractC7609s.f(this.market_logo, largeOrderItem.market_logo) && AbstractC7609s.f(this.market_name, largeOrderItem.market_name) && AbstractC7609s.f(this.orderdownBound, largeOrderItem.orderdownBound) && AbstractC7609s.f(this.completedownBound, largeOrderItem.completedownBound) && AbstractC7609s.f(this.position_sub_turnover, largeOrderItem.position_sub_turnover);
    }

    public final String getCoin() {
        return this.coin;
    }

    public final String getCoin_type() {
        return this.coin_type;
    }

    public final String getCompletedownBound() {
        return this.completedownBound;
    }

    public final String getDepth_amount() {
        return this.depth_amount;
    }

    public final Double getDepth_amount_double() {
        return this.depth_amount_double;
    }

    public final String getDepth_price() {
        return this.depth_price;
    }

    public final Double getDepth_price_double() {
        return this.depth_price_double;
    }

    public final String getDepth_state() {
        return this.depth_state;
    }

    public final Integer getDepth_state_int() {
        return this.depth_state_int;
    }

    public final String getDepth_status() {
        return this.depth_status;
    }

    public final String getDepth_turnover() {
        return this.depth_turnover;
    }

    public final String getDepth_type() {
        return this.depth_type;
    }

    public final String getDepth_vol() {
        return this.depth_vol;
    }

    public final Long getDraw_miss_time() {
        return this.draw_miss_time;
    }

    public final Long getDraw_start_time() {
        return this.draw_start_time;
    }

    public final Integer getDraw_start_time_index() {
        return this.draw_start_time_index;
    }

    public final String getFake_price() {
        return this.fake_price;
    }

    public final Double getFake_price_double() {
        return this.fake_price_double;
    }

    public final String getFilter_state() {
        return this.filter_state;
    }

    public final String getHigh_amount() {
        return this.high_amount;
    }

    public final String getHigh_trade_amount() {
        return this.high_trade_amount;
    }

    public final String getHigh_trade_turnover() {
        return this.high_trade_turnover;
    }

    public final String getHigh_vol() {
        return this.high_vol;
    }

    public final String getHold_time() {
        return this.hold_time;
    }

    public final String getId() {
        return this.id;
    }

    public final String getLast_amount() {
        return this.last_amount;
    }

    public final String getLast_turnover() {
        return this.last_turnover;
    }

    public final String getLast_vol() {
        return this.last_vol;
    }

    public final String getMarket_logo() {
        return this.market_logo;
    }

    public final String getMarket_name() {
        return this.market_name;
    }

    public final String getMiss_price() {
        return this.miss_price;
    }

    public final String getMiss_time() {
        return this.miss_time;
    }

    public final Long getMiss_time_long() {
        return this.miss_time_long;
    }

    public final String getOrder_miss_price() {
        return this.order_miss_price;
    }

    public final String getOrderdownBound() {
        return this.orderdownBound;
    }

    public final String getPlatform() {
        return this.platform;
    }

    public final String getPosition_sub() {
        return this.position_sub;
    }

    public final String getPosition_sub_turnover() {
        return this.position_sub_turnover;
    }

    public final String getRate() {
        return this.rate;
    }

    public final String getShow_state() {
        return this.show_state;
    }

    public final String getStart_time() {
        return this.start_time;
    }

    public final String getTrade_amount() {
        return this.trade_amount;
    }

    public final Double getTrade_amount_double() {
        return this.trade_amount_double;
    }

    public final String getTrade_count() {
        return this.trade_count;
    }

    public final String getTrade_miss_price() {
        return this.trade_miss_price;
    }

    public final String getTrade_price() {
        return this.trade_price;
    }

    public final String getTrade_turnover() {
        return this.trade_turnover;
    }

    public final String getTrade_type() {
        return this.trade_type;
    }

    public final String getTrade_vol() {
        return this.trade_vol;
    }

    public final String getUporder_time() {
        return this.uporder_time;
    }

    public final String getUptrade_time() {
        return this.uptrade_time;
    }

    public int hashCode() {
        String str = this.last_vol;
        int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
        String str2 = this.depth_state;
        int iHashCode2 = (iHashCode + (str2 == null ? 0 : str2.hashCode())) * 31;
        Integer num = this.depth_state_int;
        int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
        String str3 = this.high_vol;
        int iHashCode4 = (iHashCode3 + (str3 == null ? 0 : str3.hashCode())) * 31;
        String str4 = this.coin_type;
        int iHashCode5 = (iHashCode4 + (str4 == null ? 0 : str4.hashCode())) * 31;
        String str5 = this.uptrade_time;
        int iHashCode6 = (iHashCode5 + (str5 == null ? 0 : str5.hashCode())) * 31;
        String str6 = this.uporder_time;
        int iHashCode7 = (iHashCode6 + (str6 == null ? 0 : str6.hashCode())) * 31;
        String str7 = this.platform;
        int iHashCode8 = (iHashCode7 + (str7 == null ? 0 : str7.hashCode())) * 31;
        String str8 = this.start_time;
        int iHashCode9 = (iHashCode8 + (str8 == null ? 0 : str8.hashCode())) * 31;
        String str9 = this.depth_amount;
        int iHashCode10 = (iHashCode9 + (str9 == null ? 0 : str9.hashCode())) * 31;
        Double d10 = this.depth_amount_double;
        int iHashCode11 = (iHashCode10 + (d10 == null ? 0 : d10.hashCode())) * 31;
        String str10 = this.depth_vol;
        int iHashCode12 = (iHashCode11 + (str10 == null ? 0 : str10.hashCode())) * 31;
        String str11 = this.depth_status;
        int iHashCode13 = (iHashCode12 + (str11 == null ? 0 : str11.hashCode())) * 31;
        String str12 = this.fake_price;
        int iHashCode14 = (iHashCode13 + (str12 == null ? 0 : str12.hashCode())) * 31;
        Double d11 = this.fake_price_double;
        int iHashCode15 = (iHashCode14 + (d11 == null ? 0 : d11.hashCode())) * 31;
        String str13 = this.depth_price;
        int iHashCode16 = (iHashCode15 + (str13 == null ? 0 : str13.hashCode())) * 31;
        Double d12 = this.depth_price_double;
        int iHashCode17 = (iHashCode16 + (d12 == null ? 0 : d12.hashCode())) * 31;
        String str14 = this.depth_type;
        int iHashCode18 = (iHashCode17 + (str14 == null ? 0 : str14.hashCode())) * 31;
        String str15 = this.trade_amount;
        int iHashCode19 = (iHashCode18 + (str15 == null ? 0 : str15.hashCode())) * 31;
        Double d13 = this.trade_amount_double;
        int iHashCode20 = (iHashCode19 + (d13 == null ? 0 : d13.hashCode())) * 31;
        String str16 = this.trade_type;
        int iHashCode21 = (iHashCode20 + (str16 == null ? 0 : str16.hashCode())) * 31;
        String str17 = this.trade_vol;
        int iHashCode22 = (iHashCode21 + (str17 == null ? 0 : str17.hashCode())) * 31;
        String str18 = this.trade_count;
        int iHashCode23 = (iHashCode22 + (str18 == null ? 0 : str18.hashCode())) * 31;
        String str19 = this.trade_price;
        int iHashCode24 = (iHashCode23 + (str19 == null ? 0 : str19.hashCode())) * 31;
        String str20 = this.high_trade_amount;
        int iHashCode25 = (iHashCode24 + (str20 == null ? 0 : str20.hashCode())) * 31;
        String str21 = this.show_state;
        int iHashCode26 = (iHashCode25 + (str21 == null ? 0 : str21.hashCode())) * 31;
        String str22 = this.id;
        int iHashCode27 = (iHashCode26 + (str22 == null ? 0 : str22.hashCode())) * 31;
        String str23 = this.high_amount;
        int iHashCode28 = (iHashCode27 + (str23 == null ? 0 : str23.hashCode())) * 31;
        String str24 = this.last_amount;
        int iHashCode29 = (iHashCode28 + (str24 == null ? 0 : str24.hashCode())) * 31;
        String str25 = this.coin;
        int iHashCode30 = (iHashCode29 + (str25 == null ? 0 : str25.hashCode())) * 31;
        String str26 = this.miss_time;
        int iHashCode31 = (iHashCode30 + (str26 == null ? 0 : str26.hashCode())) * 31;
        Long l10 = this.miss_time_long;
        int iHashCode32 = (iHashCode31 + (l10 == null ? 0 : l10.hashCode())) * 31;
        String str27 = this.hold_time;
        int iHashCode33 = (iHashCode32 + (str27 == null ? 0 : str27.hashCode())) * 31;
        String str28 = this.miss_price;
        int iHashCode34 = (iHashCode33 + (str28 == null ? 0 : str28.hashCode())) * 31;
        String str29 = this.trade_miss_price;
        int iHashCode35 = (iHashCode34 + (str29 == null ? 0 : str29.hashCode())) * 31;
        String str30 = this.order_miss_price;
        int iHashCode36 = (iHashCode35 + (str30 == null ? 0 : str30.hashCode())) * 31;
        Long l11 = this.draw_start_time;
        int iHashCode37 = (iHashCode36 + (l11 == null ? 0 : l11.hashCode())) * 31;
        Integer num2 = this.draw_start_time_index;
        int iHashCode38 = (iHashCode37 + (num2 == null ? 0 : num2.hashCode())) * 31;
        Long l12 = this.draw_miss_time;
        int iHashCode39 = (iHashCode38 + (l12 == null ? 0 : l12.hashCode())) * 31;
        String str31 = this.rate;
        int iHashCode40 = (iHashCode39 + (str31 == null ? 0 : str31.hashCode())) * 31;
        String str32 = this.trade_turnover;
        int iHashCode41 = (iHashCode40 + (str32 == null ? 0 : str32.hashCode())) * 31;
        String str33 = this.depth_turnover;
        int iHashCode42 = (iHashCode41 + (str33 == null ? 0 : str33.hashCode())) * 31;
        String str34 = this.high_trade_turnover;
        int iHashCode43 = (iHashCode42 + (str34 == null ? 0 : str34.hashCode())) * 31;
        String str35 = this.last_turnover;
        int iHashCode44 = (iHashCode43 + (str35 == null ? 0 : str35.hashCode())) * 31;
        String str36 = this.position_sub;
        int iHashCode45 = (iHashCode44 + (str36 == null ? 0 : str36.hashCode())) * 31;
        String str37 = this.filter_state;
        int iHashCode46 = (iHashCode45 + (str37 == null ? 0 : str37.hashCode())) * 31;
        String str38 = this.market_logo;
        int iHashCode47 = (iHashCode46 + (str38 == null ? 0 : str38.hashCode())) * 31;
        String str39 = this.market_name;
        int iHashCode48 = (iHashCode47 + (str39 == null ? 0 : str39.hashCode())) * 31;
        String str40 = this.orderdownBound;
        int iHashCode49 = (iHashCode48 + (str40 == null ? 0 : str40.hashCode())) * 31;
        String str41 = this.completedownBound;
        int iHashCode50 = (iHashCode49 + (str41 == null ? 0 : str41.hashCode())) * 31;
        String str42 = this.position_sub_turnover;
        return iHashCode50 + (str42 != null ? str42.hashCode() : 0);
    }

    public final void setCoin(String str) {
        this.coin = str;
    }

    public final void setCoin_type(String str) {
        this.coin_type = str;
    }

    public final void setCompletedownBound(String str) {
        this.completedownBound = str;
    }

    public final void setDepth_amount(String str) {
        this.depth_amount = str;
    }

    public final void setDepth_amount_double(Double d10) {
        this.depth_amount_double = d10;
    }

    public final void setDepth_price(String str) {
        this.depth_price = str;
    }

    public final void setDepth_price_double(Double d10) {
        this.depth_price_double = d10;
    }

    public final void setDepth_state(String str) {
        this.depth_state = str;
    }

    public final void setDepth_state_int(Integer num) {
        this.depth_state_int = num;
    }

    public final void setDepth_status(String str) {
        this.depth_status = str;
    }

    public final void setDepth_type(String str) {
        this.depth_type = str;
    }

    public final void setDepth_vol(String str) {
        this.depth_vol = str;
    }

    public final void setDraw_miss_time(Long l10) {
        this.draw_miss_time = l10;
    }

    public final void setDraw_start_time(Long l10) {
        this.draw_start_time = l10;
    }

    public final void setDraw_start_time_index(Integer num) {
        this.draw_start_time_index = num;
    }

    public final void setFake_price(String str) {
        this.fake_price = str;
    }

    public final void setFake_price_double(Double d10) {
        this.fake_price_double = d10;
    }

    public final void setFilter_state(String str) {
        this.filter_state = str;
    }

    public final void setHigh_amount(String str) {
        this.high_amount = str;
    }

    public final void setHigh_trade_amount(String str) {
        this.high_trade_amount = str;
    }

    public final void setHigh_vol(String str) {
        this.high_vol = str;
    }

    public final void setHold_time(String str) {
        this.hold_time = str;
    }

    public final void setId(String str) {
        this.id = str;
    }

    public final void setLast_amount(String str) {
        this.last_amount = str;
    }

    public final void setLast_vol(String str) {
        this.last_vol = str;
    }

    public final void setMarket_logo(String str) {
        this.market_logo = str;
    }

    public final void setMarket_name(String str) {
        this.market_name = str;
    }

    public final void setMiss_price(String str) {
        this.miss_price = str;
    }

    public final void setMiss_time(String str) {
        this.miss_time = str;
    }

    public final void setMiss_time_long(Long l10) {
        this.miss_time_long = l10;
    }

    public final void setOrder_miss_price(String str) {
        this.order_miss_price = str;
    }

    public final void setOrderdownBound(String str) {
        this.orderdownBound = str;
    }

    public final void setPlatform(String str) {
        this.platform = str;
    }

    public final void setPosition_sub_turnover(String str) {
        this.position_sub_turnover = str;
    }

    public final void setRate(String str) {
        this.rate = str;
    }

    public final void setShow_state(String str) {
        this.show_state = str;
    }

    public final void setStart_time(String str) {
        this.start_time = str;
    }

    public final void setTrade_amount(String str) {
        this.trade_amount = str;
    }

    public final void setTrade_amount_double(Double d10) {
        this.trade_amount_double = d10;
    }

    public final void setTrade_count(String str) {
        this.trade_count = str;
    }

    public final void setTrade_miss_price(String str) {
        this.trade_miss_price = str;
    }

    public final void setTrade_price(String str) {
        this.trade_price = str;
    }

    public final void setTrade_type(String str) {
        this.trade_type = str;
    }

    public final void setTrade_vol(String str) {
        this.trade_vol = str;
    }

    public final void setUporder_time(String str) {
        this.uporder_time = str;
    }

    public final void setUptrade_time(String str) {
        this.uptrade_time = str;
    }

    public String toString() {
        return "LargeOrderItem(last_vol=" + this.last_vol + ", depth_state=" + this.depth_state + ", depth_state_int=" + this.depth_state_int + ", high_vol=" + this.high_vol + ", coin_type=" + this.coin_type + ", uptrade_time=" + this.uptrade_time + ", uporder_time=" + this.uporder_time + ", platform=" + this.platform + ", start_time=" + this.start_time + ", depth_amount=" + this.depth_amount + ", depth_amount_double=" + this.depth_amount_double + ", depth_vol=" + this.depth_vol + ", depth_status=" + this.depth_status + ", fake_price=" + this.fake_price + ", fake_price_double=" + this.fake_price_double + ", depth_price=" + this.depth_price + ", depth_price_double=" + this.depth_price_double + ", depth_type=" + this.depth_type + ", trade_amount=" + this.trade_amount + ", trade_amount_double=" + this.trade_amount_double + ", trade_type=" + this.trade_type + ", trade_vol=" + this.trade_vol + ", trade_count=" + this.trade_count + ", trade_price=" + this.trade_price + ", high_trade_amount=" + this.high_trade_amount + ", show_state=" + this.show_state + ", id=" + this.id + ", high_amount=" + this.high_amount + ", last_amount=" + this.last_amount + ", coin=" + this.coin + ", miss_time=" + this.miss_time + ", miss_time_long=" + this.miss_time_long + ", hold_time=" + this.hold_time + ", miss_price=" + this.miss_price + ", trade_miss_price=" + this.trade_miss_price + ", order_miss_price=" + this.order_miss_price + ", draw_start_time=" + this.draw_start_time + ", draw_start_time_index=" + this.draw_start_time_index + ", draw_miss_time=" + this.draw_miss_time + ", rate=" + this.rate + ", trade_turnover=" + this.trade_turnover + ", depth_turnover=" + this.depth_turnover + ", high_trade_turnover=" + this.high_trade_turnover + ", last_turnover=" + this.last_turnover + ", position_sub=" + this.position_sub + ", filter_state=" + this.filter_state + ", market_logo=" + this.market_logo + ", market_name=" + this.market_name + ", orderdownBound=" + this.orderdownBound + ", completedownBound=" + this.completedownBound + ", position_sub_turnover=" + this.position_sub_turnover + ')';
    }
}
