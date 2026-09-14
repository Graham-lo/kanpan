package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/KCRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/KCRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/KCRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/KCRemote$Input;Lsp/aicoin_kline/core/indicator/config/KCRemote$Output;Lsp/aicoin_kline/core/indicator/config/KCRemote$Output;Lsp/aicoin_kline/core/indicator/config/KCRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/KCRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/KCRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class KCRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/KCRemote$Input;", "", "cc", "", "factor", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getFactor", "component1", "component2", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/KCRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc;
        private final Integer factor;

        public Input(Integer num, Integer num2) {
            this.cc = num;
            this.factor = num2;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc;
            }
            if ((i10 & 2) != 0) {
                num2 = input.factor;
            }
            return input.copy(num, num2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc() {
            return this.cc;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getFactor() {
            return this.factor;
        }

        public final Input copy(Integer cc2, Integer factor) {
            return new Input(cc2, factor);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.cc, input.cc) && AbstractC7609s.f(this.factor, input.factor);
        }

        public final Integer getCc() {
            return this.cc;
        }

        public final Integer getFactor() {
            return this.factor;
        }

        public int hashCode() {
            Integer num = this.cc;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.factor;
            return iHashCode + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(cc=");
            sb2.append(this.cc);
            sb2.append(", factor=");
            return kk.b.a(sb2, this.factor, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b&\b\u0087\b\u0018\u00002\u00020\u0001Bs\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000e\u0010\u000fJ\u0010\u0010\u001e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u0010\u0010\u001f\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0014J\u000b\u0010 \u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u0010!\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0014J\u000b\u0010\"\u001a\u0004\u0018\u00010\u0007HÆ\u0003J\u0010\u0010#\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u0010\u0010$\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u0010\u0010%\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0014J\u000b\u0010&\u001a\u0004\u0018\u00010\u0007HÆ\u0003Jz\u0010'\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010(J\u0013\u0010)\u001a\u00020\u00032\b\u0010*\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010+\u001a\u00020\u0005HÖ\u0001J\t\u0010,\u001a\u00020\u0007HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0015\u001a\u0004\b\u0013\u0010\u0014R\u0018\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0015\u001a\u0004\b\u0018\u0010\u0014R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0017R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u001a\u0010\u0011R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u001b\u0010\u0011R\u001a\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0015\u001a\u0004\b\u001c\u0010\u0014R\u0018\u0010\r\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u0017¨\u0006-"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/KCRemote$Output;", "", "lowerDisabled", "", "lower_lineWidth", "", "lower_lineColor", "", "mid_lineWidth", "mid_lineColor", "midDisabled", "upperDisabled", "upper_lineWidth", "upper_lineColor", "<init>", "(Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;)V", "getLowerDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getLower_lineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getLower_lineColor", "()Ljava/lang/String;", "getMid_lineWidth", "getMid_lineColor", "getMidDisabled", "getUpperDisabled", "getUpper_lineWidth", "getUpper_lineColor", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "(Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/Integer;Ljava/lang/String;)Lsp/aicoin_kline/core/indicator/config/KCRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("lower_disabled")
        private final Boolean lowerDisabled;

        @SerializedName("lower_lineColor")
        private final String lower_lineColor;

        @SerializedName("lower_lineWidth")
        private final Integer lower_lineWidth;

        @SerializedName("mid_disabled")
        private final Boolean midDisabled;

        @SerializedName("mid_lineColor")
        private final String mid_lineColor;

        @SerializedName("mid_lineWidth")
        private final Integer mid_lineWidth;

        @SerializedName("upper_disabled")
        private final Boolean upperDisabled;

        @SerializedName("upper_lineColor")
        private final String upper_lineColor;

        @SerializedName("upper_lineWidth")
        private final Integer upper_lineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, 511, null);
        }

        public Output(Boolean bool, Integer num, String str, Integer num2, String str2, Boolean bool2, Boolean bool3, Integer num3, String str3) {
            this.lowerDisabled = bool;
            this.lower_lineWidth = num;
            this.lower_lineColor = str;
            this.mid_lineWidth = num2;
            this.mid_lineColor = str2;
            this.midDisabled = bool2;
            this.upperDisabled = bool3;
            this.upper_lineWidth = num3;
            this.upper_lineColor = str3;
        }

        public /* synthetic */ Output(Boolean bool, Integer num, String str, Integer num2, String str2, Boolean bool2, Boolean bool3, Integer num3, String str3, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : num, (i10 & 4) != 0 ? null : str, (i10 & 8) != 0 ? null : num2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : bool2, (i10 & 64) != 0 ? null : bool3, (i10 & 128) != 0 ? null : num3, (i10 & 256) != 0 ? null : str3);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, Integer num, String str, Integer num2, String str2, Boolean bool2, Boolean bool3, Integer num3, String str3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.lowerDisabled;
            }
            if ((i10 & 2) != 0) {
                num = output.lower_lineWidth;
            }
            if ((i10 & 4) != 0) {
                str = output.lower_lineColor;
            }
            if ((i10 & 8) != 0) {
                num2 = output.mid_lineWidth;
            }
            if ((i10 & 16) != 0) {
                str2 = output.mid_lineColor;
            }
            if ((i10 & 32) != 0) {
                bool2 = output.midDisabled;
            }
            if ((i10 & 64) != 0) {
                bool3 = output.upperDisabled;
            }
            if ((i10 & 128) != 0) {
                num3 = output.upper_lineWidth;
            }
            if ((i10 & 256) != 0) {
                str3 = output.upper_lineColor;
            }
            Integer num4 = num3;
            String str4 = str3;
            Boolean bool4 = bool2;
            Boolean bool5 = bool3;
            String str5 = str2;
            String str6 = str;
            return output.copy(bool, num, str6, num2, str5, bool4, bool5, num4, str4);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getLowerDisabled() {
            return this.lowerDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getLower_lineWidth() {
            return this.lower_lineWidth;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final String getLower_lineColor() {
            return this.lower_lineColor;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Integer getMid_lineWidth() {
            return this.mid_lineWidth;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getMid_lineColor() {
            return this.mid_lineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Boolean getMidDisabled() {
            return this.midDisabled;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getUpperDisabled() {
            return this.upperDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Integer getUpper_lineWidth() {
            return this.upper_lineWidth;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final String getUpper_lineColor() {
            return this.upper_lineColor;
        }

        public final Output copy(Boolean lowerDisabled, Integer lower_lineWidth, String lower_lineColor, Integer mid_lineWidth, String mid_lineColor, Boolean midDisabled, Boolean upperDisabled, Integer upper_lineWidth, String upper_lineColor) {
            return new Output(lowerDisabled, lower_lineWidth, lower_lineColor, mid_lineWidth, mid_lineColor, midDisabled, upperDisabled, upper_lineWidth, upper_lineColor);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.lowerDisabled, output.lowerDisabled) && AbstractC7609s.f(this.lower_lineWidth, output.lower_lineWidth) && AbstractC7609s.f(this.lower_lineColor, output.lower_lineColor) && AbstractC7609s.f(this.mid_lineWidth, output.mid_lineWidth) && AbstractC7609s.f(this.mid_lineColor, output.mid_lineColor) && AbstractC7609s.f(this.midDisabled, output.midDisabled) && AbstractC7609s.f(this.upperDisabled, output.upperDisabled) && AbstractC7609s.f(this.upper_lineWidth, output.upper_lineWidth) && AbstractC7609s.f(this.upper_lineColor, output.upper_lineColor);
        }

        public final Boolean getLowerDisabled() {
            return this.lowerDisabled;
        }

        public final String getLower_lineColor() {
            return this.lower_lineColor;
        }

        public final Integer getLower_lineWidth() {
            return this.lower_lineWidth;
        }

        public final Boolean getMidDisabled() {
            return this.midDisabled;
        }

        public final String getMid_lineColor() {
            return this.mid_lineColor;
        }

        public final Integer getMid_lineWidth() {
            return this.mid_lineWidth;
        }

        public final Boolean getUpperDisabled() {
            return this.upperDisabled;
        }

        public final String getUpper_lineColor() {
            return this.upper_lineColor;
        }

        public final Integer getUpper_lineWidth() {
            return this.upper_lineWidth;
        }

        public int hashCode() {
            Boolean bool = this.lowerDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            Integer num = this.lower_lineWidth;
            int iHashCode2 = (iHashCode + (num == null ? 0 : num.hashCode())) * 31;
            String str = this.lower_lineColor;
            int iHashCode3 = (iHashCode2 + (str == null ? 0 : str.hashCode())) * 31;
            Integer num2 = this.mid_lineWidth;
            int iHashCode4 = (iHashCode3 + (num2 == null ? 0 : num2.hashCode())) * 31;
            String str2 = this.mid_lineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Boolean bool2 = this.midDisabled;
            int iHashCode6 = (iHashCode5 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            Boolean bool3 = this.upperDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            Integer num3 = this.upper_lineWidth;
            int iHashCode8 = (iHashCode7 + (num3 == null ? 0 : num3.hashCode())) * 31;
            String str3 = this.upper_lineColor;
            return iHashCode8 + (str3 != null ? str3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(lowerDisabled=");
            sb2.append(this.lowerDisabled);
            sb2.append(", lower_lineWidth=");
            sb2.append(this.lower_lineWidth);
            sb2.append(", lower_lineColor=");
            sb2.append(this.lower_lineColor);
            sb2.append(", mid_lineWidth=");
            sb2.append(this.mid_lineWidth);
            sb2.append(", mid_lineColor=");
            sb2.append(this.mid_lineColor);
            sb2.append(", midDisabled=");
            sb2.append(this.midDisabled);
            sb2.append(", upperDisabled=");
            sb2.append(this.upperDisabled);
            sb2.append(", upper_lineWidth=");
            sb2.append(this.upper_lineWidth);
            sb2.append(", upper_lineColor=");
            return kk.h.a(sb2, this.upper_lineColor, ')');
        }
    }

    public KCRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ KCRemote copy$default(KCRemote kCRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = kCRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = kCRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = kCRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = kCRemote.app_input;
        }
        return kCRemote.copy(input, output, output2, input2);
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

    public final KCRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new KCRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof KCRemote)) {
            return false;
        }
        KCRemote kCRemote = (KCRemote) other;
        return AbstractC7609s.f(this.input, kCRemote.input) && AbstractC7609s.f(this.output, kCRemote.output) && AbstractC7609s.f(this.app_output, kCRemote.app_output) && AbstractC7609s.f(this.app_input, kCRemote.app_input);
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
        return "KCRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
