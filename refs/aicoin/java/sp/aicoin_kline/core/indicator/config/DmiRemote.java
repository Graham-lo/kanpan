package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DmiRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/DmiRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/DmiRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/DmiRemote$Input;Lsp/aicoin_kline/core/indicator/config/DmiRemote$Output;Lsp/aicoin_kline/core/indicator/config/DmiRemote$Output;Lsp/aicoin_kline/core/indicator/config/DmiRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/DmiRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/DmiRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class DmiRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DmiRemote$Input;", "", "mac1", "", "mac2", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;)V", "getMac1", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getMac2", "component1", "component2", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/DmiRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer mac1;
        private final Integer mac2;

        public Input(Integer num, Integer num2) {
            this.mac1 = num;
            this.mac2 = num2;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.mac1;
            }
            if ((i10 & 2) != 0) {
                num2 = input.mac2;
            }
            return input.copy(num, num2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getMac1() {
            return this.mac1;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getMac2() {
            return this.mac2;
        }

        public final Input copy(Integer mac1, Integer mac2) {
            return new Input(mac1, mac2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.mac1, input.mac1) && AbstractC7609s.f(this.mac2, input.mac2);
        }

        public final Integer getMac1() {
            return this.mac1;
        }

        public final Integer getMac2() {
            return this.mac2;
        }

        public int hashCode() {
            Integer num = this.mac1;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.mac2;
            return iHashCode + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(mac1=");
            sb2.append(this.mac1);
            sb2.append(", mac2=");
            return kk.b.a(sb2, this.mac2, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b/\b\u0087\b\u0018\u00002\u00020\u0001B\u0097\u0001\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u0011\u0010\u0012J\u0010\u0010$\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0014J\u000b\u0010%\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010&\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u0010'\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0014J\u000b\u0010(\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010)\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u0010*\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0014J\u000b\u0010+\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010,\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0019J\u0010\u0010-\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0014J\u000b\u0010.\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010/\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0019J\u009e\u0001\u00100\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u00101J\u0013\u00102\u001a\u00020\u00032\b\u00103\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00104\u001a\u00020\u0007HÖ\u0001J\t\u00105\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0015\u001a\u0004\b\u0013\u0010\u0014R\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b\u0018\u0010\u0019R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0015\u001a\u0004\b\u001b\u0010\u0014R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0017R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b\u001d\u0010\u0019R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0015\u001a\u0004\b\u001e\u0010\u0014R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010\u0017R\u001a\u0010\r\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b \u0010\u0019R\u001a\u0010\u000e\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0015\u001a\u0004\b!\u0010\u0014R\u0018\u0010\u000f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u0017R\u001a\u0010\u0010\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001a\u001a\u0004\b#\u0010\u0019¨\u00066"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DmiRemote$Output;", "", "adxDisabled", "", "adxLineColor", "", "adxLineWidth", "", "adxrDisabled", "adxrLineColor", "adxrLineWidth", "mdiDisabled", "mdiLineColor", "mdiLineWidth", "pdiDisabled", "pdiLineColor", "pdiLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getAdxDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getAdxLineColor", "()Ljava/lang/String;", "getAdxLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getAdxrDisabled", "getAdxrLineColor", "getAdxrLineWidth", "getMdiDisabled", "getMdiLineColor", "getMdiLineWidth", "getPdiDisabled", "getPdiLineColor", "getPdiLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/DmiRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("adx_disabled")
        private final Boolean adxDisabled;

        @SerializedName("adx_lineColor")
        private final String adxLineColor;

        @SerializedName("adx_lineWidth")
        private final Integer adxLineWidth;

        @SerializedName("adxr_disabled")
        private final Boolean adxrDisabled;

        @SerializedName("adxr_lineColor")
        private final String adxrLineColor;

        @SerializedName("adxr_lineWidth")
        private final Integer adxrLineWidth;

        @SerializedName("mdi_disabled")
        private final Boolean mdiDisabled;

        @SerializedName("mdi_lineColor")
        private final String mdiLineColor;

        @SerializedName("mdi_lineWidth")
        private final Integer mdiLineWidth;

        @SerializedName("pdi_disabled")
        private final Boolean pdiDisabled;

        @SerializedName("pdi_lineColor")
        private final String pdiLineColor;

        @SerializedName("pdi_lineWidth")
        private final Integer pdiLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, Boolean bool4, String str4, Integer num4) {
            this.adxDisabled = bool;
            this.adxLineColor = str;
            this.adxLineWidth = num;
            this.adxrDisabled = bool2;
            this.adxrLineColor = str2;
            this.adxrLineWidth = num2;
            this.mdiDisabled = bool3;
            this.mdiLineColor = str3;
            this.mdiLineWidth = num3;
            this.pdiDisabled = bool4;
            this.pdiLineColor = str4;
            this.pdiLineWidth = num4;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, Boolean bool4, String str4, Integer num4, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2, (i10 & 64) != 0 ? null : bool3, (i10 & 128) != 0 ? null : str3, (i10 & 256) != 0 ? null : num3, (i10 & 512) != 0 ? null : bool4, (i10 & 1024) != 0 ? null : str4, (i10 & 2048) != 0 ? null : num4);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, Boolean bool4, String str4, Integer num4, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.adxDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.adxLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.adxLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.adxrDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.adxrLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.adxrLineWidth;
            }
            if ((i10 & 64) != 0) {
                bool3 = output.mdiDisabled;
            }
            if ((i10 & 128) != 0) {
                str3 = output.mdiLineColor;
            }
            if ((i10 & 256) != 0) {
                num3 = output.mdiLineWidth;
            }
            if ((i10 & 512) != 0) {
                bool4 = output.pdiDisabled;
            }
            if ((i10 & 1024) != 0) {
                str4 = output.pdiLineColor;
            }
            if ((i10 & 2048) != 0) {
                num4 = output.pdiLineWidth;
            }
            String str5 = str4;
            Integer num5 = num4;
            Integer num6 = num3;
            Boolean bool5 = bool4;
            Boolean bool6 = bool3;
            String str6 = str3;
            String str7 = str2;
            Integer num7 = num2;
            return output.copy(bool, str, num, bool2, str7, num7, bool6, str6, num6, bool5, str5, num5);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getAdxDisabled() {
            return this.adxDisabled;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final Boolean getPdiDisabled() {
            return this.pdiDisabled;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final String getPdiLineColor() {
            return this.pdiLineColor;
        }

        /* JADX INFO: renamed from: component12, reason: from getter */
        public final Integer getPdiLineWidth() {
            return this.pdiLineWidth;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getAdxLineColor() {
            return this.adxLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getAdxLineWidth() {
            return this.adxLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getAdxrDisabled() {
            return this.adxrDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getAdxrLineColor() {
            return this.adxrLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getAdxrLineWidth() {
            return this.adxrLineWidth;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getMdiDisabled() {
            return this.mdiDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final String getMdiLineColor() {
            return this.mdiLineColor;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Integer getMdiLineWidth() {
            return this.mdiLineWidth;
        }

        public final Output copy(Boolean adxDisabled, String adxLineColor, Integer adxLineWidth, Boolean adxrDisabled, String adxrLineColor, Integer adxrLineWidth, Boolean mdiDisabled, String mdiLineColor, Integer mdiLineWidth, Boolean pdiDisabled, String pdiLineColor, Integer pdiLineWidth) {
            return new Output(adxDisabled, adxLineColor, adxLineWidth, adxrDisabled, adxrLineColor, adxrLineWidth, mdiDisabled, mdiLineColor, mdiLineWidth, pdiDisabled, pdiLineColor, pdiLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.adxDisabled, output.adxDisabled) && AbstractC7609s.f(this.adxLineColor, output.adxLineColor) && AbstractC7609s.f(this.adxLineWidth, output.adxLineWidth) && AbstractC7609s.f(this.adxrDisabled, output.adxrDisabled) && AbstractC7609s.f(this.adxrLineColor, output.adxrLineColor) && AbstractC7609s.f(this.adxrLineWidth, output.adxrLineWidth) && AbstractC7609s.f(this.mdiDisabled, output.mdiDisabled) && AbstractC7609s.f(this.mdiLineColor, output.mdiLineColor) && AbstractC7609s.f(this.mdiLineWidth, output.mdiLineWidth) && AbstractC7609s.f(this.pdiDisabled, output.pdiDisabled) && AbstractC7609s.f(this.pdiLineColor, output.pdiLineColor) && AbstractC7609s.f(this.pdiLineWidth, output.pdiLineWidth);
        }

        public final Boolean getAdxDisabled() {
            return this.adxDisabled;
        }

        public final String getAdxLineColor() {
            return this.adxLineColor;
        }

        public final Integer getAdxLineWidth() {
            return this.adxLineWidth;
        }

        public final Boolean getAdxrDisabled() {
            return this.adxrDisabled;
        }

        public final String getAdxrLineColor() {
            return this.adxrLineColor;
        }

        public final Integer getAdxrLineWidth() {
            return this.adxrLineWidth;
        }

        public final Boolean getMdiDisabled() {
            return this.mdiDisabled;
        }

        public final String getMdiLineColor() {
            return this.mdiLineColor;
        }

        public final Integer getMdiLineWidth() {
            return this.mdiLineWidth;
        }

        public final Boolean getPdiDisabled() {
            return this.pdiDisabled;
        }

        public final String getPdiLineColor() {
            return this.pdiLineColor;
        }

        public final Integer getPdiLineWidth() {
            return this.pdiLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.adxDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.adxLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.adxLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.adxrDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.adxrLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.adxrLineWidth;
            int iHashCode6 = (iHashCode5 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool3 = this.mdiDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.mdiLineColor;
            int iHashCode8 = (iHashCode7 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num3 = this.mdiLineWidth;
            int iHashCode9 = (iHashCode8 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Boolean bool4 = this.pdiDisabled;
            int iHashCode10 = (iHashCode9 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            String str4 = this.pdiLineColor;
            int iHashCode11 = (iHashCode10 + (str4 == null ? 0 : str4.hashCode())) * 31;
            Integer num4 = this.pdiLineWidth;
            return iHashCode11 + (num4 != null ? num4.hashCode() : 0);
        }

        public String toString() {
            return "Output(adxDisabled=" + this.adxDisabled + ", adxLineColor=" + this.adxLineColor + ", adxLineWidth=" + this.adxLineWidth + ", adxrDisabled=" + this.adxrDisabled + ", adxrLineColor=" + this.adxrLineColor + ", adxrLineWidth=" + this.adxrLineWidth + ", mdiDisabled=" + this.mdiDisabled + ", mdiLineColor=" + this.mdiLineColor + ", mdiLineWidth=" + this.mdiLineWidth + ", pdiDisabled=" + this.pdiDisabled + ", pdiLineColor=" + this.pdiLineColor + ", pdiLineWidth=" + this.pdiLineWidth + ')';
        }
    }

    public DmiRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ DmiRemote copy$default(DmiRemote dmiRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = dmiRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = dmiRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = dmiRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = dmiRemote.app_input;
        }
        return dmiRemote.copy(input, output, output2, input2);
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

    public final DmiRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new DmiRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof DmiRemote)) {
            return false;
        }
        DmiRemote dmiRemote = (DmiRemote) other;
        return AbstractC7609s.f(this.input, dmiRemote.input) && AbstractC7609s.f(this.output, dmiRemote.output) && AbstractC7609s.f(this.app_output, dmiRemote.app_output) && AbstractC7609s.f(this.app_input, dmiRemote.app_input);
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
        return "DmiRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
