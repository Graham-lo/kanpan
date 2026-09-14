package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ENERemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/ENERemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/ENERemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/ENERemote$Input;Lsp/aicoin_kline/core/indicator/config/ENERemote$Output;Lsp/aicoin_kline/core/indicator/config/ENERemote$Output;Lsp/aicoin_kline/core/indicator/config/ENERemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/ENERemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/ENERemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ENERemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u000f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B%\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0006\u0010\u0007J\u0010\u0010\r\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ2\u0010\u0010\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u0011J\u0013\u0010\u0012\u001a\u00020\u00132\b\u0010\u0014\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\b\u0010\tR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\u000b\u0010\tR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\f\u0010\t¨\u0006\u0018"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ENERemote$Input;", "", "cc1", "", "cc2", "cc3", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getCc1", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getCc2", "getCc3", "component1", "component2", "component3", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/ENERemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc1;
        private final Integer cc2;
        private final Integer cc3;

        public Input(Integer num, Integer num2, Integer num3) {
            this.cc1 = num;
            this.cc2 = num2;
            this.cc3 = num3;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc1;
            }
            if ((i10 & 2) != 0) {
                num2 = input.cc2;
            }
            if ((i10 & 4) != 0) {
                num3 = input.cc3;
            }
            return input.copy(num, num2, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc1() {
            return this.cc1;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getCc2() {
            return this.cc2;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getCc3() {
            return this.cc3;
        }

        public final Input copy(Integer cc1, Integer cc2, Integer cc3) {
            return new Input(cc1, cc2, cc3);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.cc1, input.cc1) && AbstractC7609s.f(this.cc2, input.cc2) && AbstractC7609s.f(this.cc3, input.cc3);
        }

        public final Integer getCc1() {
            return this.cc1;
        }

        public final Integer getCc2() {
            return this.cc2;
        }

        public final Integer getCc3() {
            return this.cc3;
        }

        public int hashCode() {
            Integer num = this.cc1;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.cc2;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.cc3;
            return iHashCode2 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(cc1=");
            sb2.append(this.cc1);
            sb2.append(", cc2=");
            sb2.append(this.cc2);
            sb2.append(", cc3=");
            return kk.b.a(sb2, this.cc3, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b2\b\u0087\b\u0018\u00002\u00020\u0001Bs\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000e\u0010\u000fJ\u0010\u0010*\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u0010\u0010+\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0016J\u000b\u0010,\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u0010-\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u0010\u0010.\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0016J\u000b\u0010/\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u00100\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u0010\u00101\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0016J\u000b\u00102\u001a\u0004\u0018\u00010\u0007HÆ\u0003Jz\u00103\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u00104J\u0013\u00105\u001a\u00020\u00032\b\u00106\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00107\u001a\u00020\u0005HÖ\u0001J\t\u00108\u001a\u00020\u0007HÖ\u0001R\"\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006@\u0006X\u0087\u000e¢\u0006\u0010\n\u0002\u0010\u0014\u001a\u0004\b\u0010\u0010\u0011\"\u0004\b\u0012\u0010\u0013R\"\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006@\u0006X\u0087\u000e¢\u0006\u0010\n\u0002\u0010\u0019\u001a\u0004\b\u0015\u0010\u0016\"\u0004\b\u0017\u0010\u0018R \u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006@\u0006X\u0087\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001a\u0010\u001b\"\u0004\b\u001c\u0010\u001dR\"\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006@\u0006X\u0087\u000e¢\u0006\u0010\n\u0002\u0010\u0014\u001a\u0004\b\u001e\u0010\u0011\"\u0004\b\u001f\u0010\u0013R\"\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006@\u0006X\u0087\u000e¢\u0006\u0010\n\u0002\u0010\u0019\u001a\u0004\b \u0010\u0016\"\u0004\b!\u0010\u0018R \u0010\n\u001a\u0004\u0018\u00010\u00078\u0006@\u0006X\u0087\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\"\u0010\u001b\"\u0004\b#\u0010\u001dR\"\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006@\u0006X\u0087\u000e¢\u0006\u0010\n\u0002\u0010\u0014\u001a\u0004\b$\u0010\u0011\"\u0004\b%\u0010\u0013R\"\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006@\u0006X\u0087\u000e¢\u0006\u0010\n\u0002\u0010\u0019\u001a\u0004\b&\u0010\u0016\"\u0004\b'\u0010\u0018R \u0010\r\u001a\u0004\u0018\u00010\u00078\u0006@\u0006X\u0087\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b(\u0010\u001b\"\u0004\b)\u0010\u001d¨\u00069"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ENERemote$Output;", "", "midDisabled", "", "midLineWidth", "", "midLineColor", "", "upperDisabled", "upperLineWidth", "upperLineColor", "lowerDisabled", "lowerLineWidth", "lowerLineColor", "<init>", "(Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;)V", "getMidDisabled", "()Ljava/lang/Boolean;", "setMidDisabled", "(Ljava/lang/Boolean;)V", "Ljava/lang/Boolean;", "getMidLineWidth", "()Ljava/lang/Integer;", "setMidLineWidth", "(Ljava/lang/Integer;)V", "Ljava/lang/Integer;", "getMidLineColor", "()Ljava/lang/String;", "setMidLineColor", "(Ljava/lang/String;)V", "getUpperDisabled", "setUpperDisabled", "getUpperLineWidth", "setUpperLineWidth", "getUpperLineColor", "setUpperLineColor", "getLowerDisabled", "setLowerDisabled", "getLowerLineWidth", "setLowerLineWidth", "getLowerLineColor", "setLowerLineColor", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "(Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;)Lsp/aicoin_kline/core/indicator/config/ENERemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("lower_disabled")
        private Boolean lowerDisabled;

        @SerializedName("lower_lineColor")
        private String lowerLineColor;

        @SerializedName("lower_lineWidth")
        private Integer lowerLineWidth;

        @SerializedName("mid_disabled")
        private Boolean midDisabled;

        @SerializedName("mid_lineColor")
        private String midLineColor;

        @SerializedName("mid_lineWidth")
        private Integer midLineWidth;

        @SerializedName("upper_disabled")
        private Boolean upperDisabled;

        @SerializedName("upper_lineColor")
        private String upperLineColor;

        @SerializedName("upper_lineWidth")
        private Integer upperLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, 511, null);
        }

        public Output(Boolean bool, Integer num, String str, Boolean bool2, Integer num2, String str2, Boolean bool3, Integer num3, String str3) {
            this.midDisabled = bool;
            this.midLineWidth = num;
            this.midLineColor = str;
            this.upperDisabled = bool2;
            this.upperLineWidth = num2;
            this.upperLineColor = str2;
            this.lowerDisabled = bool3;
            this.lowerLineWidth = num3;
            this.lowerLineColor = str3;
        }

        public /* synthetic */ Output(Boolean bool, Integer num, String str, Boolean bool2, Integer num2, String str2, Boolean bool3, Integer num3, String str3, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : num, (i10 & 4) != 0 ? null : str, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : num2, (i10 & 32) != 0 ? null : str2, (i10 & 64) != 0 ? null : bool3, (i10 & 128) != 0 ? null : num3, (i10 & 256) != 0 ? null : str3);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, Integer num, String str, Boolean bool2, Integer num2, String str2, Boolean bool3, Integer num3, String str3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.midDisabled;
            }
            if ((i10 & 2) != 0) {
                num = output.midLineWidth;
            }
            if ((i10 & 4) != 0) {
                str = output.midLineColor;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.upperDisabled;
            }
            if ((i10 & 16) != 0) {
                num2 = output.upperLineWidth;
            }
            if ((i10 & 32) != 0) {
                str2 = output.upperLineColor;
            }
            if ((i10 & 64) != 0) {
                bool3 = output.lowerDisabled;
            }
            if ((i10 & 128) != 0) {
                num3 = output.lowerLineWidth;
            }
            if ((i10 & 256) != 0) {
                str3 = output.lowerLineColor;
            }
            Integer num4 = num3;
            String str4 = str3;
            String str5 = str2;
            Boolean bool4 = bool3;
            Integer num5 = num2;
            String str6 = str;
            return output.copy(bool, num, str6, bool2, num5, str5, bool4, num4, str4);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getMidDisabled() {
            return this.midDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getMidLineWidth() {
            return this.midLineWidth;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final String getMidLineColor() {
            return this.midLineColor;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getUpperDisabled() {
            return this.upperDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getUpperLineWidth() {
            return this.upperLineWidth;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final String getUpperLineColor() {
            return this.upperLineColor;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getLowerDisabled() {
            return this.lowerDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Integer getLowerLineWidth() {
            return this.lowerLineWidth;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final String getLowerLineColor() {
            return this.lowerLineColor;
        }

        public final Output copy(Boolean midDisabled, Integer midLineWidth, String midLineColor, Boolean upperDisabled, Integer upperLineWidth, String upperLineColor, Boolean lowerDisabled, Integer lowerLineWidth, String lowerLineColor) {
            return new Output(midDisabled, midLineWidth, midLineColor, upperDisabled, upperLineWidth, upperLineColor, lowerDisabled, lowerLineWidth, lowerLineColor);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.midDisabled, output.midDisabled) && AbstractC7609s.f(this.midLineWidth, output.midLineWidth) && AbstractC7609s.f(this.midLineColor, output.midLineColor) && AbstractC7609s.f(this.upperDisabled, output.upperDisabled) && AbstractC7609s.f(this.upperLineWidth, output.upperLineWidth) && AbstractC7609s.f(this.upperLineColor, output.upperLineColor) && AbstractC7609s.f(this.lowerDisabled, output.lowerDisabled) && AbstractC7609s.f(this.lowerLineWidth, output.lowerLineWidth) && AbstractC7609s.f(this.lowerLineColor, output.lowerLineColor);
        }

        public final Boolean getLowerDisabled() {
            return this.lowerDisabled;
        }

        public final String getLowerLineColor() {
            return this.lowerLineColor;
        }

        public final Integer getLowerLineWidth() {
            return this.lowerLineWidth;
        }

        public final Boolean getMidDisabled() {
            return this.midDisabled;
        }

        public final String getMidLineColor() {
            return this.midLineColor;
        }

        public final Integer getMidLineWidth() {
            return this.midLineWidth;
        }

        public final Boolean getUpperDisabled() {
            return this.upperDisabled;
        }

        public final String getUpperLineColor() {
            return this.upperLineColor;
        }

        public final Integer getUpperLineWidth() {
            return this.upperLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.midDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            Integer num = this.midLineWidth;
            int iHashCode2 = (iHashCode + (num == null ? 0 : num.hashCode())) * 31;
            String str = this.midLineColor;
            int iHashCode3 = (iHashCode2 + (str == null ? 0 : str.hashCode())) * 31;
            Boolean bool2 = this.upperDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            Integer num2 = this.upperLineWidth;
            int iHashCode5 = (iHashCode4 + (num2 == null ? 0 : num2.hashCode())) * 31;
            String str2 = this.upperLineColor;
            int iHashCode6 = (iHashCode5 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Boolean bool3 = this.lowerDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            Integer num3 = this.lowerLineWidth;
            int iHashCode8 = (iHashCode7 + (num3 == null ? 0 : num3.hashCode())) * 31;
            String str3 = this.lowerLineColor;
            return iHashCode8 + (str3 != null ? str3.hashCode() : 0);
        }

        public final void setLowerDisabled(Boolean bool) {
            this.lowerDisabled = bool;
        }

        public final void setLowerLineColor(String str) {
            this.lowerLineColor = str;
        }

        public final void setLowerLineWidth(Integer num) {
            this.lowerLineWidth = num;
        }

        public final void setMidDisabled(Boolean bool) {
            this.midDisabled = bool;
        }

        public final void setMidLineColor(String str) {
            this.midLineColor = str;
        }

        public final void setMidLineWidth(Integer num) {
            this.midLineWidth = num;
        }

        public final void setUpperDisabled(Boolean bool) {
            this.upperDisabled = bool;
        }

        public final void setUpperLineColor(String str) {
            this.upperLineColor = str;
        }

        public final void setUpperLineWidth(Integer num) {
            this.upperLineWidth = num;
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(midDisabled=");
            sb2.append(this.midDisabled);
            sb2.append(", midLineWidth=");
            sb2.append(this.midLineWidth);
            sb2.append(", midLineColor=");
            sb2.append(this.midLineColor);
            sb2.append(", upperDisabled=");
            sb2.append(this.upperDisabled);
            sb2.append(", upperLineWidth=");
            sb2.append(this.upperLineWidth);
            sb2.append(", upperLineColor=");
            sb2.append(this.upperLineColor);
            sb2.append(", lowerDisabled=");
            sb2.append(this.lowerDisabled);
            sb2.append(", lowerLineWidth=");
            sb2.append(this.lowerLineWidth);
            sb2.append(", lowerLineColor=");
            return kk.h.a(sb2, this.lowerLineColor, ')');
        }
    }

    public ENERemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ ENERemote copy$default(ENERemote eNERemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = eNERemote.input;
        }
        if ((i10 & 2) != 0) {
            output = eNERemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = eNERemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = eNERemote.app_input;
        }
        return eNERemote.copy(input, output, output2, input2);
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

    public final ENERemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new ENERemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ENERemote)) {
            return false;
        }
        ENERemote eNERemote = (ENERemote) other;
        return AbstractC7609s.f(this.input, eNERemote.input) && AbstractC7609s.f(this.output, eNERemote.output) && AbstractC7609s.f(this.app_output, eNERemote.app_output) && AbstractC7609s.f(this.app_input, eNERemote.app_input);
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
        return "ENERemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
