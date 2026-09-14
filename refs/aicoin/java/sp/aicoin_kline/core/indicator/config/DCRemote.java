package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DCRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/DCRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/DCRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/DCRemote$Input;Lsp/aicoin_kline/core/indicator/config/DCRemote$Output;Lsp/aicoin_kline/core/indicator/config/DCRemote$Output;Lsp/aicoin_kline/core/indicator/config/DCRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/DCRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/DCRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class DCRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\t\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u0011\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0004\u0010\u0005J\u0010\u0010\t\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0007J\u001a\u0010\n\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000bJ\u0013\u0010\f\u001a\u00020\r2\b\u0010\u000e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000f\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\b\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0012"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DCRemote$Input;", "", "cc", "", "<init>", "(Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "copy", "(Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/DCRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc;

        public Input(Integer num) {
            this.cc = num;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc;
            }
            return input.copy(num);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc() {
            return this.cc;
        }

        public final Input copy(Integer cc2) {
            return new Input(cc2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Input) && AbstractC7609s.f(this.cc, ((Input) other).cc);
        }

        public final Integer getCc() {
            return this.cc;
        }

        public int hashCode() {
            Integer num = this.cc;
            if (num == null) {
                return 0;
            }
            return num.hashCode();
        }

        public String toString() {
            return kk.b.a(new StringBuilder("Input(cc="), this.cc, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b)\b\u0087\b\u0018\u00002\u00020\u0001B\u007f\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u000f\u0010\u0010J\u0010\u0010 \u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0012J\u000b\u0010!\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\"\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0017J\u0010\u0010#\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0012J\u000b\u0010$\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010%\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0017J\u0010\u0010&\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0012J\u000b\u0010'\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010(\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0017J\u0010\u0010)\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0012J\u0086\u0001\u0010*\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010+J\u0013\u0010,\u001a\u00020\u00032\b\u0010-\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010.\u001a\u00020\u0007HÖ\u0001J\t\u0010/\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0013\u001a\u0004\b\u0011\u0010\u0012R\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0014\u0010\u0015R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b\u0016\u0010\u0017R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0013\u001a\u0004\b\u0019\u0010\u0012R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u0015R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b\u001b\u0010\u0017R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0013\u001a\u0004\b\u001c\u0010\u0012R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u0015R\u001a\u0010\r\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b\u001e\u0010\u0017R\u001a\u0010\u000e\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0013\u001a\u0004\b\u001f\u0010\u0012¨\u00060"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/DCRemote$Output;", "", "midDisabled", "", "midLineColor", "", "midLineWidth", "", "upperDisabled", "upperLineColor", "upperLineWidth", "lowerDisabled", "lowerLineColor", "lowerLineWidth", "backgroundDisabled", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;)V", "getMidDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getMidLineColor", "()Ljava/lang/String;", "getMidLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getUpperDisabled", "getUpperLineColor", "getUpperLineWidth", "getLowerDisabled", "getLowerLineColor", "getLowerLineWidth", "getBackgroundDisabled", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/DCRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("background_disabled")
        private final Boolean backgroundDisabled;

        @SerializedName("lower_disabled")
        private final Boolean lowerDisabled;

        @SerializedName("lower_lineColor")
        private final String lowerLineColor;

        @SerializedName("lower_lineWidth")
        private final Integer lowerLineWidth;

        @SerializedName("mid_disabled")
        private final Boolean midDisabled;

        @SerializedName("mid_lineColor")
        private final String midLineColor;

        @SerializedName("mid_lineWidth")
        private final Integer midLineWidth;

        @SerializedName("upper_disabled")
        private final Boolean upperDisabled;

        @SerializedName("upper_lineColor")
        private final String upperLineColor;

        @SerializedName("upper_lineWidth")
        private final Integer upperLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, 1023, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, Boolean bool4) {
            this.midDisabled = bool;
            this.midLineColor = str;
            this.midLineWidth = num;
            this.upperDisabled = bool2;
            this.upperLineColor = str2;
            this.upperLineWidth = num2;
            this.lowerDisabled = bool3;
            this.lowerLineColor = str3;
            this.lowerLineWidth = num3;
            this.backgroundDisabled = bool4;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, Boolean bool4, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? Boolean.FALSE : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? Boolean.FALSE : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2, (i10 & 64) != 0 ? Boolean.FALSE : bool3, (i10 & 128) != 0 ? null : str3, (i10 & 256) != 0 ? null : num3, (i10 & 512) != 0 ? Boolean.FALSE : bool4);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, Boolean bool4, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.midDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.midLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.midLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.upperDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.upperLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.upperLineWidth;
            }
            if ((i10 & 64) != 0) {
                bool3 = output.lowerDisabled;
            }
            if ((i10 & 128) != 0) {
                str3 = output.lowerLineColor;
            }
            if ((i10 & 256) != 0) {
                num3 = output.lowerLineWidth;
            }
            if ((i10 & 512) != 0) {
                bool4 = output.backgroundDisabled;
            }
            Integer num4 = num3;
            Boolean bool5 = bool4;
            Boolean bool6 = bool3;
            String str4 = str3;
            String str5 = str2;
            Integer num5 = num2;
            return output.copy(bool, str, num, bool2, str5, num5, bool6, str4, num4, bool5);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getMidDisabled() {
            return this.midDisabled;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final Boolean getBackgroundDisabled() {
            return this.backgroundDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getMidLineColor() {
            return this.midLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getMidLineWidth() {
            return this.midLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getUpperDisabled() {
            return this.upperDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getUpperLineColor() {
            return this.upperLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getUpperLineWidth() {
            return this.upperLineWidth;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getLowerDisabled() {
            return this.lowerDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final String getLowerLineColor() {
            return this.lowerLineColor;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Integer getLowerLineWidth() {
            return this.lowerLineWidth;
        }

        public final Output copy(Boolean midDisabled, String midLineColor, Integer midLineWidth, Boolean upperDisabled, String upperLineColor, Integer upperLineWidth, Boolean lowerDisabled, String lowerLineColor, Integer lowerLineWidth, Boolean backgroundDisabled) {
            return new Output(midDisabled, midLineColor, midLineWidth, upperDisabled, upperLineColor, upperLineWidth, lowerDisabled, lowerLineColor, lowerLineWidth, backgroundDisabled);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.midDisabled, output.midDisabled) && AbstractC7609s.f(this.midLineColor, output.midLineColor) && AbstractC7609s.f(this.midLineWidth, output.midLineWidth) && AbstractC7609s.f(this.upperDisabled, output.upperDisabled) && AbstractC7609s.f(this.upperLineColor, output.upperLineColor) && AbstractC7609s.f(this.upperLineWidth, output.upperLineWidth) && AbstractC7609s.f(this.lowerDisabled, output.lowerDisabled) && AbstractC7609s.f(this.lowerLineColor, output.lowerLineColor) && AbstractC7609s.f(this.lowerLineWidth, output.lowerLineWidth) && AbstractC7609s.f(this.backgroundDisabled, output.backgroundDisabled);
        }

        public final Boolean getBackgroundDisabled() {
            return this.backgroundDisabled;
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
            String str = this.midLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.midLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.upperDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.upperLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.upperLineWidth;
            int iHashCode6 = (iHashCode5 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool3 = this.lowerDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.lowerLineColor;
            int iHashCode8 = (iHashCode7 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num3 = this.lowerLineWidth;
            int iHashCode9 = (iHashCode8 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Boolean bool4 = this.backgroundDisabled;
            return iHashCode9 + (bool4 != null ? bool4.hashCode() : 0);
        }

        public String toString() {
            return "Output(midDisabled=" + this.midDisabled + ", midLineColor=" + this.midLineColor + ", midLineWidth=" + this.midLineWidth + ", upperDisabled=" + this.upperDisabled + ", upperLineColor=" + this.upperLineColor + ", upperLineWidth=" + this.upperLineWidth + ", lowerDisabled=" + this.lowerDisabled + ", lowerLineColor=" + this.lowerLineColor + ", lowerLineWidth=" + this.lowerLineWidth + ", backgroundDisabled=" + this.backgroundDisabled + ')';
        }
    }

    public DCRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ DCRemote copy$default(DCRemote dCRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = dCRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = dCRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = dCRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = dCRemote.app_input;
        }
        return dCRemote.copy(input, output, output2, input2);
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

    public final DCRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new DCRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof DCRemote)) {
            return false;
        }
        DCRemote dCRemote = (DCRemote) other;
        return AbstractC7609s.f(this.input, dCRemote.input) && AbstractC7609s.f(this.output, dCRemote.output) && AbstractC7609s.f(this.app_output, dCRemote.app_output) && AbstractC7609s.f(this.app_input, dCRemote.app_input);
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
        return "DCRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
