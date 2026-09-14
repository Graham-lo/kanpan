package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import com.tencent.wcdb.database.SQLiteGlobal;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.dnsoverhttps.DnsOverHttps;
import okhttp3.internal.http2.Http2;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/RsiRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/RsiRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/RsiRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/RsiRemote$Input;Lsp/aicoin_kline/core/indicator/config/RsiRemote$Output;Lsp/aicoin_kline/core/indicator/config/RsiRemote$Output;Lsp/aicoin_kline/core/indicator/config/RsiRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/RsiRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/RsiRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class RsiRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0018\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001BC\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\b\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\t\u0010\nJ\u0010\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0015\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0016\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0017\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJV\u0010\u0019\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u001aJ\u0013\u0010\u001b\u001a\u00020\u001c2\b\u0010\u001d\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001e\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001f\u001a\u00020 HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000b\u0010\fR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000e\u0010\fR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000f\u0010\fR\u0015\u0010\u0006\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0010\u0010\fR\u0015\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0011\u0010\fR\u0015\u0010\b\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0012\u0010\f¨\u0006!"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/RsiRemote$Input;", "", "lowerBand", "", "middleBand", "mac1", "mac2", "mac3", "upperBand", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getLowerBand", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMiddleBand", "getMac1", "getMac2", "getMac3", "getUpperBand", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/RsiRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer lowerBand;
        private final Integer mac1;
        private final Integer mac2;
        private final Integer mac3;
        private final Integer middleBand;
        private final Integer upperBand;

        public Input(Integer num, Integer num2, Integer num3, Integer num4, Integer num5, Integer num6) {
            this.lowerBand = num;
            this.middleBand = num2;
            this.mac1 = num3;
            this.mac2 = num4;
            this.mac3 = num5;
            this.upperBand = num6;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, Integer num4, Integer num5, Integer num6, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.lowerBand;
            }
            if ((i10 & 2) != 0) {
                num2 = input.middleBand;
            }
            if ((i10 & 4) != 0) {
                num3 = input.mac1;
            }
            if ((i10 & 8) != 0) {
                num4 = input.mac2;
            }
            if ((i10 & 16) != 0) {
                num5 = input.mac3;
            }
            if ((i10 & 32) != 0) {
                num6 = input.upperBand;
            }
            Integer num7 = num5;
            Integer num8 = num6;
            return input.copy(num, num2, num3, num4, num7, num8);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getLowerBand() {
            return this.lowerBand;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getMiddleBand() {
            return this.middleBand;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getMac1() {
            return this.mac1;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Integer getMac2() {
            return this.mac2;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getMac3() {
            return this.mac3;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getUpperBand() {
            return this.upperBand;
        }

        public final Input copy(Integer lowerBand, Integer middleBand, Integer mac1, Integer mac2, Integer mac3, Integer upperBand) {
            return new Input(lowerBand, middleBand, mac1, mac2, mac3, upperBand);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.lowerBand, input.lowerBand) && AbstractC7609s.f(this.middleBand, input.middleBand) && AbstractC7609s.f(this.mac1, input.mac1) && AbstractC7609s.f(this.mac2, input.mac2) && AbstractC7609s.f(this.mac3, input.mac3) && AbstractC7609s.f(this.upperBand, input.upperBand);
        }

        public final Integer getLowerBand() {
            return this.lowerBand;
        }

        public final Integer getMac1() {
            return this.mac1;
        }

        public final Integer getMac2() {
            return this.mac2;
        }

        public final Integer getMac3() {
            return this.mac3;
        }

        public final Integer getMiddleBand() {
            return this.middleBand;
        }

        public final Integer getUpperBand() {
            return this.upperBand;
        }

        public int hashCode() {
            Integer num = this.lowerBand;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.middleBand;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.mac1;
            int iHashCode3 = (iHashCode2 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Integer num4 = this.mac2;
            int iHashCode4 = (iHashCode3 + (num4 == null ? 0 : num4.hashCode())) * 31;
            Integer num5 = this.mac3;
            int iHashCode5 = (iHashCode4 + (num5 == null ? 0 : num5.hashCode())) * 31;
            Integer num6 = this.upperBand;
            return iHashCode5 + (num6 != null ? num6.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(lowerBand=");
            sb2.append(this.lowerBand);
            sb2.append(", middleBand=");
            sb2.append(this.middleBand);
            sb2.append(", mac1=");
            sb2.append(this.mac1);
            sb2.append(", mac2=");
            sb2.append(this.mac2);
            sb2.append(", mac3=");
            sb2.append(this.mac3);
            sb2.append(", upperBand=");
            return kk.b.a(sb2, this.upperBand, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\bH\b\u0087\b\u0018\u00002\u00020\u0001B\u0083\u0002\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\u0017\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\t¢\u0006\u0004\b\u001a\u0010\u001bJ\u000b\u00106\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u00107\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001fJ\u0010\u00108\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001fJ\u000b\u00109\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010:\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010$J\u0010\u0010;\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001fJ\u000b\u0010<\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010=\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010$J\u0010\u0010>\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010$J\u0010\u0010?\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001fJ\u000b\u0010@\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010A\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010$J\u0010\u0010B\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001fJ\u000b\u0010C\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010D\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010$J\u0010\u0010E\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001fJ\u000b\u0010F\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010G\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010$J\u0010\u0010H\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001fJ\u000b\u0010I\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010J\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010$J\u008a\u0002\u0010K\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0016\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\u0017\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0018\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\tHÆ\u0001¢\u0006\u0002\u0010LJ\u0013\u0010M\u001a\u00020\u00052\b\u0010N\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010O\u001a\u00020\tHÖ\u0001J\t\u0010P\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u001dR\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010 \u001a\u0004\b\u001e\u0010\u001fR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010 \u001a\u0004\b!\u0010\u001fR\u0018\u0010\u0007\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u001dR\u001a\u0010\b\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010%\u001a\u0004\b#\u0010$R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010 \u001a\u0004\b&\u0010\u001fR\u0018\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b'\u0010\u001dR\u001a\u0010\f\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010%\u001a\u0004\b(\u0010$R\u001a\u0010\r\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010%\u001a\u0004\b)\u0010$R\u001a\u0010\u000e\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010 \u001a\u0004\b*\u0010\u001fR\u0018\u0010\u000f\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b+\u0010\u001dR\u001a\u0010\u0010\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010%\u001a\u0004\b,\u0010$R\u001a\u0010\u0011\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010 \u001a\u0004\b-\u0010\u001fR\u0018\u0010\u0012\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b.\u0010\u001dR\u001a\u0010\u0013\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010%\u001a\u0004\b/\u0010$R\u001a\u0010\u0014\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010 \u001a\u0004\b0\u0010\u001fR\u0018\u0010\u0015\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b1\u0010\u001dR\u001a\u0010\u0016\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010%\u001a\u0004\b2\u0010$R\u001a\u0010\u0017\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010 \u001a\u0004\b3\u0010\u001fR\u0018\u0010\u0018\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b4\u0010\u001dR\u001a\u0010\u0019\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010%\u001a\u0004\b5\u0010$¨\u0006Q"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/RsiRemote$Output;", "", "bandAreaBackground", "", "bandAreaDisabled", "", "lowerBandDisabled", "lowerBandLineColor", "lowerBandLineWidth", "", "middleBandDisabled", "middleBandLineColor", "middleBandLineStyle", "middleBandLineWidth", "rsi1Disabled", "rsi1LineColor", "rsi1LineWidth", "rsi2Disabled", "rsi2LineColor", "rsi2LineWidth", "rsi3Disabled", "rsi3LineColor", "rsi3LineWidth", "upperBandDisabled", "upperBandLineColor", "upperBandLineWidth", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getBandAreaBackground", "()Ljava/lang/String;", "getBandAreaDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getLowerBandDisabled", "getLowerBandLineColor", "getLowerBandLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMiddleBandDisabled", "getMiddleBandLineColor", "getMiddleBandLineStyle", "getMiddleBandLineWidth", "getRsi1Disabled", "getRsi1LineColor", "getRsi1LineWidth", "getRsi2Disabled", "getRsi2LineColor", "getRsi2LineWidth", "getRsi3Disabled", "getRsi3LineColor", "getRsi3LineWidth", "getUpperBandDisabled", "getUpperBandLineColor", "getUpperBandLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component19", "component20", "component21", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/RsiRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("bandArea_background")
        private final String bandAreaBackground;

        @SerializedName("bandArea_disabled")
        private final Boolean bandAreaDisabled;

        @SerializedName("lowerBand_disabled")
        private final Boolean lowerBandDisabled;

        @SerializedName("lowerBand_lineColor")
        private final String lowerBandLineColor;

        @SerializedName("lowerBand_lineWidth")
        private final Integer lowerBandLineWidth;

        @SerializedName("middleBand_disabled")
        private final Boolean middleBandDisabled;

        @SerializedName("middleBand_lineColor")
        private final String middleBandLineColor;

        @SerializedName("middleBand_lineStyle")
        private final Integer middleBandLineStyle;

        @SerializedName("middleBand_lineWidth")
        private final Integer middleBandLineWidth;

        @SerializedName("rsi1_disabled")
        private final Boolean rsi1Disabled;

        @SerializedName("rsi1_lineColor")
        private final String rsi1LineColor;

        @SerializedName("rsi1_lineWidth")
        private final Integer rsi1LineWidth;

        @SerializedName("rsi2_disabled")
        private final Boolean rsi2Disabled;

        @SerializedName("rsi2_lineColor")
        private final String rsi2LineColor;

        @SerializedName("rsi2_lineWidth")
        private final Integer rsi2LineWidth;

        @SerializedName("rsi3_disabled")
        private final Boolean rsi3Disabled;

        @SerializedName("rsi3_lineColor")
        private final String rsi3LineColor;

        @SerializedName("rsi3_lineWidth")
        private final Integer rsi3LineWidth;

        @SerializedName("upperBand_disabled")
        private final Boolean upperBandDisabled;

        @SerializedName("upperBand_lineColor")
        private final String upperBandLineColor;

        @SerializedName("upperBand_lineWidth")
        private final Integer upperBandLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, 2097151, null);
        }

        public Output(String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Integer num3, Boolean bool4, String str4, Integer num4, Boolean bool5, String str5, Integer num5, Boolean bool6, String str6, Integer num6, Boolean bool7, String str7, Integer num7) {
            this.bandAreaBackground = str;
            this.bandAreaDisabled = bool;
            this.lowerBandDisabled = bool2;
            this.lowerBandLineColor = str2;
            this.lowerBandLineWidth = num;
            this.middleBandDisabled = bool3;
            this.middleBandLineColor = str3;
            this.middleBandLineStyle = num2;
            this.middleBandLineWidth = num3;
            this.rsi1Disabled = bool4;
            this.rsi1LineColor = str4;
            this.rsi1LineWidth = num4;
            this.rsi2Disabled = bool5;
            this.rsi2LineColor = str5;
            this.rsi2LineWidth = num5;
            this.rsi3Disabled = bool6;
            this.rsi3LineColor = str6;
            this.rsi3LineWidth = num6;
            this.upperBandDisabled = bool7;
            this.upperBandLineColor = str7;
            this.upperBandLineWidth = num7;
        }

        public /* synthetic */ Output(String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Integer num3, Boolean bool4, String str4, Integer num4, Boolean bool5, String str5, Integer num5, Boolean bool6, String str6, Integer num6, Boolean bool7, String str7, Integer num7, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, (i10 & 2) != 0 ? null : bool, (i10 & 4) != 0 ? null : bool2, (i10 & 8) != 0 ? null : str2, (i10 & 16) != 0 ? null : num, (i10 & 32) != 0 ? null : bool3, (i10 & 64) != 0 ? null : str3, (i10 & 128) != 0 ? null : num2, (i10 & 256) != 0 ? null : num3, (i10 & 512) != 0 ? null : bool4, (i10 & 1024) != 0 ? null : str4, (i10 & 2048) != 0 ? null : num4, (i10 & 4096) != 0 ? null : bool5, (i10 & 8192) != 0 ? null : str5, (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? null : num5, (i10 & 32768) != 0 ? null : bool6, (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? null : str6, (i10 & 131072) != 0 ? null : num6, (i10 & 262144) != 0 ? null : bool7, (i10 & SQLiteGlobal.journalSizeLimit) != 0 ? null : str7, (i10 & 1048576) != 0 ? null : num7);
        }

        public static /* synthetic */ Output copy$default(Output output, String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Integer num3, Boolean bool4, String str4, Integer num4, Boolean bool5, String str5, Integer num5, Boolean bool6, String str6, Integer num6, Boolean bool7, String str7, Integer num7, int i10, Object obj) {
            Integer num8;
            String str8;
            String str9 = (i10 & 1) != 0 ? output.bandAreaBackground : str;
            Boolean bool8 = (i10 & 2) != 0 ? output.bandAreaDisabled : bool;
            Boolean bool9 = (i10 & 4) != 0 ? output.lowerBandDisabled : bool2;
            String str10 = (i10 & 8) != 0 ? output.lowerBandLineColor : str2;
            Integer num9 = (i10 & 16) != 0 ? output.lowerBandLineWidth : num;
            Boolean bool10 = (i10 & 32) != 0 ? output.middleBandDisabled : bool3;
            String str11 = (i10 & 64) != 0 ? output.middleBandLineColor : str3;
            Integer num10 = (i10 & 128) != 0 ? output.middleBandLineStyle : num2;
            Integer num11 = (i10 & 256) != 0 ? output.middleBandLineWidth : num3;
            Boolean bool11 = (i10 & 512) != 0 ? output.rsi1Disabled : bool4;
            String str12 = (i10 & 1024) != 0 ? output.rsi1LineColor : str4;
            Integer num12 = (i10 & 2048) != 0 ? output.rsi1LineWidth : num4;
            Boolean bool12 = (i10 & 4096) != 0 ? output.rsi2Disabled : bool5;
            String str13 = (i10 & 8192) != 0 ? output.rsi2LineColor : str5;
            String str14 = str9;
            Integer num13 = (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? output.rsi2LineWidth : num5;
            Boolean bool13 = (i10 & 32768) != 0 ? output.rsi3Disabled : bool6;
            String str15 = (i10 & DnsOverHttps.MAX_RESPONSE_SIZE) != 0 ? output.rsi3LineColor : str6;
            Integer num14 = (i10 & 131072) != 0 ? output.rsi3LineWidth : num6;
            Boolean bool14 = (i10 & 262144) != 0 ? output.upperBandDisabled : bool7;
            String str16 = (i10 & SQLiteGlobal.journalSizeLimit) != 0 ? output.upperBandLineColor : str7;
            if ((i10 & 1048576) != 0) {
                str8 = str16;
                num8 = output.upperBandLineWidth;
            } else {
                num8 = num7;
                str8 = str16;
            }
            return output.copy(str14, bool8, bool9, str10, num9, bool10, str11, num10, num11, bool11, str12, num12, bool12, str13, num13, bool13, str15, num14, bool14, str8, num8);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getBandAreaBackground() {
            return this.bandAreaBackground;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final Boolean getRsi1Disabled() {
            return this.rsi1Disabled;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final String getRsi1LineColor() {
            return this.rsi1LineColor;
        }

        /* JADX INFO: renamed from: component12, reason: from getter */
        public final Integer getRsi1LineWidth() {
            return this.rsi1LineWidth;
        }

        /* JADX INFO: renamed from: component13, reason: from getter */
        public final Boolean getRsi2Disabled() {
            return this.rsi2Disabled;
        }

        /* JADX INFO: renamed from: component14, reason: from getter */
        public final String getRsi2LineColor() {
            return this.rsi2LineColor;
        }

        /* JADX INFO: renamed from: component15, reason: from getter */
        public final Integer getRsi2LineWidth() {
            return this.rsi2LineWidth;
        }

        /* JADX INFO: renamed from: component16, reason: from getter */
        public final Boolean getRsi3Disabled() {
            return this.rsi3Disabled;
        }

        /* JADX INFO: renamed from: component17, reason: from getter */
        public final String getRsi3LineColor() {
            return this.rsi3LineColor;
        }

        /* JADX INFO: renamed from: component18, reason: from getter */
        public final Integer getRsi3LineWidth() {
            return this.rsi3LineWidth;
        }

        /* JADX INFO: renamed from: component19, reason: from getter */
        public final Boolean getUpperBandDisabled() {
            return this.upperBandDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getBandAreaDisabled() {
            return this.bandAreaDisabled;
        }

        /* JADX INFO: renamed from: component20, reason: from getter */
        public final String getUpperBandLineColor() {
            return this.upperBandLineColor;
        }

        /* JADX INFO: renamed from: component21, reason: from getter */
        public final Integer getUpperBandLineWidth() {
            return this.upperBandLineWidth;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getLowerBandDisabled() {
            return this.lowerBandDisabled;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final String getLowerBandLineColor() {
            return this.lowerBandLineColor;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getLowerBandLineWidth() {
            return this.lowerBandLineWidth;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Boolean getMiddleBandDisabled() {
            return this.middleBandDisabled;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final String getMiddleBandLineColor() {
            return this.middleBandLineColor;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Integer getMiddleBandLineStyle() {
            return this.middleBandLineStyle;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Integer getMiddleBandLineWidth() {
            return this.middleBandLineWidth;
        }

        public final Output copy(String bandAreaBackground, Boolean bandAreaDisabled, Boolean lowerBandDisabled, String lowerBandLineColor, Integer lowerBandLineWidth, Boolean middleBandDisabled, String middleBandLineColor, Integer middleBandLineStyle, Integer middleBandLineWidth, Boolean rsi1Disabled, String rsi1LineColor, Integer rsi1LineWidth, Boolean rsi2Disabled, String rsi2LineColor, Integer rsi2LineWidth, Boolean rsi3Disabled, String rsi3LineColor, Integer rsi3LineWidth, Boolean upperBandDisabled, String upperBandLineColor, Integer upperBandLineWidth) {
            return new Output(bandAreaBackground, bandAreaDisabled, lowerBandDisabled, lowerBandLineColor, lowerBandLineWidth, middleBandDisabled, middleBandLineColor, middleBandLineStyle, middleBandLineWidth, rsi1Disabled, rsi1LineColor, rsi1LineWidth, rsi2Disabled, rsi2LineColor, rsi2LineWidth, rsi3Disabled, rsi3LineColor, rsi3LineWidth, upperBandDisabled, upperBandLineColor, upperBandLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.bandAreaBackground, output.bandAreaBackground) && AbstractC7609s.f(this.bandAreaDisabled, output.bandAreaDisabled) && AbstractC7609s.f(this.lowerBandDisabled, output.lowerBandDisabled) && AbstractC7609s.f(this.lowerBandLineColor, output.lowerBandLineColor) && AbstractC7609s.f(this.lowerBandLineWidth, output.lowerBandLineWidth) && AbstractC7609s.f(this.middleBandDisabled, output.middleBandDisabled) && AbstractC7609s.f(this.middleBandLineColor, output.middleBandLineColor) && AbstractC7609s.f(this.middleBandLineStyle, output.middleBandLineStyle) && AbstractC7609s.f(this.middleBandLineWidth, output.middleBandLineWidth) && AbstractC7609s.f(this.rsi1Disabled, output.rsi1Disabled) && AbstractC7609s.f(this.rsi1LineColor, output.rsi1LineColor) && AbstractC7609s.f(this.rsi1LineWidth, output.rsi1LineWidth) && AbstractC7609s.f(this.rsi2Disabled, output.rsi2Disabled) && AbstractC7609s.f(this.rsi2LineColor, output.rsi2LineColor) && AbstractC7609s.f(this.rsi2LineWidth, output.rsi2LineWidth) && AbstractC7609s.f(this.rsi3Disabled, output.rsi3Disabled) && AbstractC7609s.f(this.rsi3LineColor, output.rsi3LineColor) && AbstractC7609s.f(this.rsi3LineWidth, output.rsi3LineWidth) && AbstractC7609s.f(this.upperBandDisabled, output.upperBandDisabled) && AbstractC7609s.f(this.upperBandLineColor, output.upperBandLineColor) && AbstractC7609s.f(this.upperBandLineWidth, output.upperBandLineWidth);
        }

        public final String getBandAreaBackground() {
            return this.bandAreaBackground;
        }

        public final Boolean getBandAreaDisabled() {
            return this.bandAreaDisabled;
        }

        public final Boolean getLowerBandDisabled() {
            return this.lowerBandDisabled;
        }

        public final String getLowerBandLineColor() {
            return this.lowerBandLineColor;
        }

        public final Integer getLowerBandLineWidth() {
            return this.lowerBandLineWidth;
        }

        public final Boolean getMiddleBandDisabled() {
            return this.middleBandDisabled;
        }

        public final String getMiddleBandLineColor() {
            return this.middleBandLineColor;
        }

        public final Integer getMiddleBandLineStyle() {
            return this.middleBandLineStyle;
        }

        public final Integer getMiddleBandLineWidth() {
            return this.middleBandLineWidth;
        }

        public final Boolean getRsi1Disabled() {
            return this.rsi1Disabled;
        }

        public final String getRsi1LineColor() {
            return this.rsi1LineColor;
        }

        public final Integer getRsi1LineWidth() {
            return this.rsi1LineWidth;
        }

        public final Boolean getRsi2Disabled() {
            return this.rsi2Disabled;
        }

        public final String getRsi2LineColor() {
            return this.rsi2LineColor;
        }

        public final Integer getRsi2LineWidth() {
            return this.rsi2LineWidth;
        }

        public final Boolean getRsi3Disabled() {
            return this.rsi3Disabled;
        }

        public final String getRsi3LineColor() {
            return this.rsi3LineColor;
        }

        public final Integer getRsi3LineWidth() {
            return this.rsi3LineWidth;
        }

        public final Boolean getUpperBandDisabled() {
            return this.upperBandDisabled;
        }

        public final String getUpperBandLineColor() {
            return this.upperBandLineColor;
        }

        public final Integer getUpperBandLineWidth() {
            return this.upperBandLineWidth;
        }

        public int hashCode() {
            String str = this.bandAreaBackground;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            Boolean bool = this.bandAreaDisabled;
            int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
            Boolean bool2 = this.lowerBandDisabled;
            int iHashCode3 = (iHashCode2 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.lowerBandLineColor;
            int iHashCode4 = (iHashCode3 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num = this.lowerBandLineWidth;
            int iHashCode5 = (iHashCode4 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool3 = this.middleBandDisabled;
            int iHashCode6 = (iHashCode5 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.middleBandLineColor;
            int iHashCode7 = (iHashCode6 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num2 = this.middleBandLineStyle;
            int iHashCode8 = (iHashCode7 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.middleBandLineWidth;
            int iHashCode9 = (iHashCode8 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Boolean bool4 = this.rsi1Disabled;
            int iHashCode10 = (iHashCode9 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            String str4 = this.rsi1LineColor;
            int iHashCode11 = (iHashCode10 + (str4 == null ? 0 : str4.hashCode())) * 31;
            Integer num4 = this.rsi1LineWidth;
            int iHashCode12 = (iHashCode11 + (num4 == null ? 0 : num4.hashCode())) * 31;
            Boolean bool5 = this.rsi2Disabled;
            int iHashCode13 = (iHashCode12 + (bool5 == null ? 0 : bool5.hashCode())) * 31;
            String str5 = this.rsi2LineColor;
            int iHashCode14 = (iHashCode13 + (str5 == null ? 0 : str5.hashCode())) * 31;
            Integer num5 = this.rsi2LineWidth;
            int iHashCode15 = (iHashCode14 + (num5 == null ? 0 : num5.hashCode())) * 31;
            Boolean bool6 = this.rsi3Disabled;
            int iHashCode16 = (iHashCode15 + (bool6 == null ? 0 : bool6.hashCode())) * 31;
            String str6 = this.rsi3LineColor;
            int iHashCode17 = (iHashCode16 + (str6 == null ? 0 : str6.hashCode())) * 31;
            Integer num6 = this.rsi3LineWidth;
            int iHashCode18 = (iHashCode17 + (num6 == null ? 0 : num6.hashCode())) * 31;
            Boolean bool7 = this.upperBandDisabled;
            int iHashCode19 = (iHashCode18 + (bool7 == null ? 0 : bool7.hashCode())) * 31;
            String str7 = this.upperBandLineColor;
            int iHashCode20 = (iHashCode19 + (str7 == null ? 0 : str7.hashCode())) * 31;
            Integer num7 = this.upperBandLineWidth;
            return iHashCode20 + (num7 != null ? num7.hashCode() : 0);
        }

        public String toString() {
            return "Output(bandAreaBackground=" + this.bandAreaBackground + ", bandAreaDisabled=" + this.bandAreaDisabled + ", lowerBandDisabled=" + this.lowerBandDisabled + ", lowerBandLineColor=" + this.lowerBandLineColor + ", lowerBandLineWidth=" + this.lowerBandLineWidth + ", middleBandDisabled=" + this.middleBandDisabled + ", middleBandLineColor=" + this.middleBandLineColor + ", middleBandLineStyle=" + this.middleBandLineStyle + ", middleBandLineWidth=" + this.middleBandLineWidth + ", rsi1Disabled=" + this.rsi1Disabled + ", rsi1LineColor=" + this.rsi1LineColor + ", rsi1LineWidth=" + this.rsi1LineWidth + ", rsi2Disabled=" + this.rsi2Disabled + ", rsi2LineColor=" + this.rsi2LineColor + ", rsi2LineWidth=" + this.rsi2LineWidth + ", rsi3Disabled=" + this.rsi3Disabled + ", rsi3LineColor=" + this.rsi3LineColor + ", rsi3LineWidth=" + this.rsi3LineWidth + ", upperBandDisabled=" + this.upperBandDisabled + ", upperBandLineColor=" + this.upperBandLineColor + ", upperBandLineWidth=" + this.upperBandLineWidth + ')';
        }
    }

    public RsiRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ RsiRemote copy$default(RsiRemote rsiRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = rsiRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = rsiRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = rsiRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = rsiRemote.app_input;
        }
        return rsiRemote.copy(input, output, output2, input2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Input getInput() {
        return this.input;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final Input getApp_input() {
        return this.app_input;
    }

    public final RsiRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new RsiRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof RsiRemote)) {
            return false;
        }
        RsiRemote rsiRemote = (RsiRemote) other;
        return AbstractC7609s.f(this.input, rsiRemote.input) && AbstractC7609s.f(this.output, rsiRemote.output) && AbstractC7609s.f(this.app_output, rsiRemote.app_output) && AbstractC7609s.f(this.app_input, rsiRemote.app_input);
    }

    public final Input getApp_input() {
        return this.app_input;
    }

    public final Output getApp_output() {
        return this.app_output;
    }

    public final Input getInput() {
        return this.input;
    }

    public final Output getOutput() {
        return this.output;
    }

    public int hashCode() {
        Input input = this.input;
        int iHashCode = (input == null ? 0 : input.hashCode()) * 31;
        Output output = this.output;
        int iHashCode2 = (iHashCode + (output == null ? 0 : output.hashCode())) * 31;
        Output output2 = this.app_output;
        int iHashCode3 = (iHashCode2 + (output2 == null ? 0 : output2.hashCode())) * 31;
        Input input2 = this.app_input;
        return iHashCode3 + (input2 != null ? input2.hashCode() : 0);
    }

    public String toString() {
        return "RsiRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
