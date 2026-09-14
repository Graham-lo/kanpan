package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.internal.http2.Http2;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/MACDRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/MACDRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/MACDRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/MACDRemote$Input;Lsp/aicoin_kline/core/indicator/config/MACDRemote$Output;Lsp/aicoin_kline/core/indicator/config/MACDRemote$Output;Lsp/aicoin_kline/core/indicator/config/MACDRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/MACDRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/MACDRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class MACDRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u000f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B%\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0006\u0010\u0007J\u0010\u0010\r\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ2\u0010\u0010\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u0011J\u0013\u0010\u0012\u001a\u00020\u00132\b\u0010\u0014\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\b\u0010\tR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\u000b\u0010\tR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\f\u0010\t¨\u0006\u0018"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/MACDRemote$Input;", "", "lc", "", "mac", "sc", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getLc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMac", "getSc", "component1", "component2", "component3", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/MACDRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer lc;
        private final Integer mac;
        private final Integer sc;

        public Input(Integer num, Integer num2, Integer num3) {
            this.lc = num;
            this.mac = num2;
            this.sc = num3;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.lc;
            }
            if ((i10 & 2) != 0) {
                num2 = input.mac;
            }
            if ((i10 & 4) != 0) {
                num3 = input.sc;
            }
            return input.copy(num, num2, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getLc() {
            return this.lc;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getMac() {
            return this.mac;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getSc() {
            return this.sc;
        }

        public final Input copy(Integer lc2, Integer mac, Integer sc2) {
            return new Input(lc2, mac, sc2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.lc, input.lc) && AbstractC7609s.f(this.mac, input.mac) && AbstractC7609s.f(this.sc, input.sc);
        }

        public final Integer getLc() {
            return this.lc;
        }

        public final Integer getMac() {
            return this.mac;
        }

        public final Integer getSc() {
            return this.sc;
        }

        public int hashCode() {
            Integer num = this.lc;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.mac;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.sc;
            return iHashCode2 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(lc=");
            sb2.append(this.lc);
            sb2.append(", mac=");
            sb2.append(this.mac);
            sb2.append(", sc=");
            return kk.b.a(sb2, this.sc, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b8\b\u0087\b\u0018\u00002\u00020\u0001B»\u0001\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0014\u0010\u0015J\u0010\u0010*\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u000b\u0010+\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010,\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u0010\u0010-\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u000b\u0010.\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010/\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u0010\u00100\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u000b\u00101\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u00102\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u000b\u00103\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u00104\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u000b\u00105\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u00106\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u000b\u00107\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u00108\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017JÂ\u0001\u00109\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010:J\u0013\u0010;\u001a\u00020\u00032\b\u0010<\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010=\u001a\u00020\u0007HÖ\u0001J\t\u0010>\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b\u0016\u0010\u0017R\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u001aR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001d\u001a\u0004\b\u001b\u0010\u001cR\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b\u001e\u0010\u0017R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010\u001aR\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001d\u001a\u0004\b \u0010\u001cR\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b!\u0010\u0017R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u001aR\u001a\u0010\r\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b#\u0010\u0017R\u0018\u0010\u000e\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b$\u0010\u001aR\u001a\u0010\u000f\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b%\u0010\u0017R\u0018\u0010\u0010\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b&\u0010\u001aR\u001a\u0010\u0011\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b'\u0010\u0017R\u0018\u0010\u0012\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b(\u0010\u001aR\u001a\u0010\u0013\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b)\u0010\u0017¨\u0006?"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/MACDRemote$Output;", "", "deaDisabled", "", "deaLineColor", "", "deaLineWidth", "", "difDisabled", "difLineColor", "difLineWidth", "macdDisabled", "macdNegFallColor", "macdNegFallFill", "macdNegRiseColor", "macdNegRiseFill", "macdPosFallColor", "macdPosFallFill", "macdPosRiseColor", "macdPosRiseFill", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;)V", "getDeaDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getDeaLineColor", "()Ljava/lang/String;", "getDeaLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getDifDisabled", "getDifLineColor", "getDifLineWidth", "getMacdDisabled", "getMacdNegFallColor", "getMacdNegFallFill", "getMacdNegRiseColor", "getMacdNegRiseFill", "getMacdPosFallColor", "getMacdPosFallFill", "getMacdPosRiseColor", "getMacdPosRiseFill", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "component14", "component15", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/MACDRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("dea_disabled")
        private final Boolean deaDisabled;

        @SerializedName("dea_lineColor")
        private final String deaLineColor;

        @SerializedName("dea_lineWidth")
        private final Integer deaLineWidth;

        @SerializedName("dif_disabled")
        private final Boolean difDisabled;

        @SerializedName("dif_lineColor")
        private final String difLineColor;

        @SerializedName("dif_lineWidth")
        private final Integer difLineWidth;

        @SerializedName("macd_disabled")
        private final Boolean macdDisabled;

        @SerializedName("macd_negFall_color")
        private final String macdNegFallColor;

        @SerializedName("macd_negFall_fill")
        private final Boolean macdNegFallFill;

        @SerializedName("macd_negRise_color")
        private final String macdNegRiseColor;

        @SerializedName("macd_negRise_fill")
        private final Boolean macdNegRiseFill;

        @SerializedName("macd_posFall_color")
        private final String macdPosFallColor;

        @SerializedName("macd_posFall_fill")
        private final Boolean macdPosFallFill;

        @SerializedName("macd_posRise_color")
        private final String macdPosRiseColor;

        @SerializedName("macd_posRise_fill")
        private final Boolean macdPosRiseFill;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, 32767, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Boolean bool4, String str4, Boolean bool5, String str5, Boolean bool6, String str6, Boolean bool7) {
            this.deaDisabled = bool;
            this.deaLineColor = str;
            this.deaLineWidth = num;
            this.difDisabled = bool2;
            this.difLineColor = str2;
            this.difLineWidth = num2;
            this.macdDisabled = bool3;
            this.macdNegFallColor = str3;
            this.macdNegFallFill = bool4;
            this.macdNegRiseColor = str4;
            this.macdNegRiseFill = bool5;
            this.macdPosFallColor = str5;
            this.macdPosFallFill = bool6;
            this.macdPosRiseColor = str6;
            this.macdPosRiseFill = bool7;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Boolean bool4, String str4, Boolean bool5, String str5, Boolean bool6, String str6, Boolean bool7, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? Boolean.FALSE : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? Boolean.FALSE : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2, (i10 & 64) != 0 ? Boolean.FALSE : bool3, (i10 & 128) != 0 ? null : str3, (i10 & 256) != 0 ? null : bool4, (i10 & 512) != 0 ? null : str4, (i10 & 1024) != 0 ? null : bool5, (i10 & 2048) != 0 ? null : str5, (i10 & 4096) != 0 ? null : bool6, (i10 & 8192) != 0 ? null : str6, (i10 & Http2.INITIAL_MAX_FRAME_SIZE) != 0 ? null : bool7);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getDeaDisabled() {
            return this.deaDisabled;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final String getMacdNegRiseColor() {
            return this.macdNegRiseColor;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final Boolean getMacdNegRiseFill() {
            return this.macdNegRiseFill;
        }

        /* JADX INFO: renamed from: component12, reason: from getter */
        public final String getMacdPosFallColor() {
            return this.macdPosFallColor;
        }

        /* JADX INFO: renamed from: component13, reason: from getter */
        public final Boolean getMacdPosFallFill() {
            return this.macdPosFallFill;
        }

        /* JADX INFO: renamed from: component14, reason: from getter */
        public final String getMacdPosRiseColor() {
            return this.macdPosRiseColor;
        }

        /* JADX INFO: renamed from: component15, reason: from getter */
        public final Boolean getMacdPosRiseFill() {
            return this.macdPosRiseFill;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getDeaLineColor() {
            return this.deaLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getDeaLineWidth() {
            return this.deaLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getDifDisabled() {
            return this.difDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getDifLineColor() {
            return this.difLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getDifLineWidth() {
            return this.difLineWidth;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getMacdDisabled() {
            return this.macdDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final String getMacdNegFallColor() {
            return this.macdNegFallColor;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Boolean getMacdNegFallFill() {
            return this.macdNegFallFill;
        }

        public final Output copy(Boolean deaDisabled, String deaLineColor, Integer deaLineWidth, Boolean difDisabled, String difLineColor, Integer difLineWidth, Boolean macdDisabled, String macdNegFallColor, Boolean macdNegFallFill, String macdNegRiseColor, Boolean macdNegRiseFill, String macdPosFallColor, Boolean macdPosFallFill, String macdPosRiseColor, Boolean macdPosRiseFill) {
            return new Output(deaDisabled, deaLineColor, deaLineWidth, difDisabled, difLineColor, difLineWidth, macdDisabled, macdNegFallColor, macdNegFallFill, macdNegRiseColor, macdNegRiseFill, macdPosFallColor, macdPosFallFill, macdPosRiseColor, macdPosRiseFill);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.deaDisabled, output.deaDisabled) && AbstractC7609s.f(this.deaLineColor, output.deaLineColor) && AbstractC7609s.f(this.deaLineWidth, output.deaLineWidth) && AbstractC7609s.f(this.difDisabled, output.difDisabled) && AbstractC7609s.f(this.difLineColor, output.difLineColor) && AbstractC7609s.f(this.difLineWidth, output.difLineWidth) && AbstractC7609s.f(this.macdDisabled, output.macdDisabled) && AbstractC7609s.f(this.macdNegFallColor, output.macdNegFallColor) && AbstractC7609s.f(this.macdNegFallFill, output.macdNegFallFill) && AbstractC7609s.f(this.macdNegRiseColor, output.macdNegRiseColor) && AbstractC7609s.f(this.macdNegRiseFill, output.macdNegRiseFill) && AbstractC7609s.f(this.macdPosFallColor, output.macdPosFallColor) && AbstractC7609s.f(this.macdPosFallFill, output.macdPosFallFill) && AbstractC7609s.f(this.macdPosRiseColor, output.macdPosRiseColor) && AbstractC7609s.f(this.macdPosRiseFill, output.macdPosRiseFill);
        }

        public final Boolean getDeaDisabled() {
            return this.deaDisabled;
        }

        public final String getDeaLineColor() {
            return this.deaLineColor;
        }

        public final Integer getDeaLineWidth() {
            return this.deaLineWidth;
        }

        public final Boolean getDifDisabled() {
            return this.difDisabled;
        }

        public final String getDifLineColor() {
            return this.difLineColor;
        }

        public final Integer getDifLineWidth() {
            return this.difLineWidth;
        }

        public final Boolean getMacdDisabled() {
            return this.macdDisabled;
        }

        public final String getMacdNegFallColor() {
            return this.macdNegFallColor;
        }

        public final Boolean getMacdNegFallFill() {
            return this.macdNegFallFill;
        }

        public final String getMacdNegRiseColor() {
            return this.macdNegRiseColor;
        }

        public final Boolean getMacdNegRiseFill() {
            return this.macdNegRiseFill;
        }

        public final String getMacdPosFallColor() {
            return this.macdPosFallColor;
        }

        public final Boolean getMacdPosFallFill() {
            return this.macdPosFallFill;
        }

        public final String getMacdPosRiseColor() {
            return this.macdPosRiseColor;
        }

        public final Boolean getMacdPosRiseFill() {
            return this.macdPosRiseFill;
        }

        public int hashCode() {
            Boolean bool = this.deaDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.deaLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.deaLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.difDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.difLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.difLineWidth;
            int iHashCode6 = (iHashCode5 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool3 = this.macdDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.macdNegFallColor;
            int iHashCode8 = (iHashCode7 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Boolean bool4 = this.macdNegFallFill;
            int iHashCode9 = (iHashCode8 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            String str4 = this.macdNegRiseColor;
            int iHashCode10 = (iHashCode9 + (str4 == null ? 0 : str4.hashCode())) * 31;
            Boolean bool5 = this.macdNegRiseFill;
            int iHashCode11 = (iHashCode10 + (bool5 == null ? 0 : bool5.hashCode())) * 31;
            String str5 = this.macdPosFallColor;
            int iHashCode12 = (iHashCode11 + (str5 == null ? 0 : str5.hashCode())) * 31;
            Boolean bool6 = this.macdPosFallFill;
            int iHashCode13 = (iHashCode12 + (bool6 == null ? 0 : bool6.hashCode())) * 31;
            String str6 = this.macdPosRiseColor;
            int iHashCode14 = (iHashCode13 + (str6 == null ? 0 : str6.hashCode())) * 31;
            Boolean bool7 = this.macdPosRiseFill;
            return iHashCode14 + (bool7 != null ? bool7.hashCode() : 0);
        }

        public String toString() {
            return "Output(deaDisabled=" + this.deaDisabled + ", deaLineColor=" + this.deaLineColor + ", deaLineWidth=" + this.deaLineWidth + ", difDisabled=" + this.difDisabled + ", difLineColor=" + this.difLineColor + ", difLineWidth=" + this.difLineWidth + ", macdDisabled=" + this.macdDisabled + ", macdNegFallColor=" + this.macdNegFallColor + ", macdNegFallFill=" + this.macdNegFallFill + ", macdNegRiseColor=" + this.macdNegRiseColor + ", macdNegRiseFill=" + this.macdNegRiseFill + ", macdPosFallColor=" + this.macdPosFallColor + ", macdPosFallFill=" + this.macdPosFallFill + ", macdPosRiseColor=" + this.macdPosRiseColor + ", macdPosRiseFill=" + this.macdPosRiseFill + ')';
        }
    }

    public MACDRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ MACDRemote copy$default(MACDRemote mACDRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = mACDRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = mACDRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = mACDRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = mACDRemote.app_input;
        }
        return mACDRemote.copy(input, output, output2, input2);
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

    public final MACDRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new MACDRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof MACDRemote)) {
            return false;
        }
        MACDRemote mACDRemote = (MACDRemote) other;
        return AbstractC7609s.f(this.input, mACDRemote.input) && AbstractC7609s.f(this.output, mACDRemote.output) && AbstractC7609s.f(this.app_output, mACDRemote.app_output) && AbstractC7609s.f(this.app_input, mACDRemote.app_input);
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
        return "MACDRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
