package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/CCIRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/CCIRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/CCIRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/CCIRemote$Input;Lsp/aicoin_kline/core/indicator/config/CCIRemote$Output;Lsp/aicoin_kline/core/indicator/config/CCIRemote$Output;Lsp/aicoin_kline/core/indicator/config/CCIRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/CCIRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/CCIRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class CCIRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u000f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B%\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0006\u0010\u0007J\u0010\u0010\r\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ2\u0010\u0010\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u0011J\u0013\u0010\u0012\u001a\u00020\u00132\b\u0010\u0014\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\b\u0010\tR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\u000b\u0010\tR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\f\u0010\t¨\u0006\u0018"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/CCIRemote$Input;", "", "cc", "", "lowerBand", "upperBand", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getCc", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getLowerBand", "getUpperBand", "component1", "component2", "component3", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/CCIRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer cc;
        private final Integer lowerBand;
        private final Integer upperBand;

        public Input(Integer num, Integer num2, Integer num3) {
            this.cc = num;
            this.lowerBand = num2;
            this.upperBand = num3;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.cc;
            }
            if ((i10 & 2) != 0) {
                num2 = input.lowerBand;
            }
            if ((i10 & 4) != 0) {
                num3 = input.upperBand;
            }
            return input.copy(num, num2, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getCc() {
            return this.cc;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getLowerBand() {
            return this.lowerBand;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getUpperBand() {
            return this.upperBand;
        }

        public final Input copy(Integer cc2, Integer lowerBand, Integer upperBand) {
            return new Input(cc2, lowerBand, upperBand);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.cc, input.cc) && AbstractC7609s.f(this.lowerBand, input.lowerBand) && AbstractC7609s.f(this.upperBand, input.upperBand);
        }

        public final Integer getCc() {
            return this.cc;
        }

        public final Integer getLowerBand() {
            return this.lowerBand;
        }

        public final Integer getUpperBand() {
            return this.upperBand;
        }

        public int hashCode() {
            Integer num = this.cc;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.lowerBand;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.upperBand;
            return iHashCode2 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(cc=");
            sb2.append(this.cc);
            sb2.append(", lowerBand=");
            sb2.append(this.lowerBand);
            sb2.append(", upperBand=");
            return kk.b.a(sb2, this.upperBand, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\b*\b\u0087\b\u0018\u00002\u00020\u0001B\u008b\u0001\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\t\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\t¢\u0006\u0004\b\u0010\u0010\u0011J\u000b\u0010\"\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010#\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u0010\u0010$\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u000b\u0010%\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010&\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010\u001aJ\u0010\u0010'\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u000b\u0010(\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010)\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010\u001aJ\u0010\u0010*\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u000b\u0010+\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010,\u001a\u0004\u0018\u00010\tHÆ\u0003¢\u0006\u0002\u0010\u001aJ\u0092\u0001\u0010-\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\t2\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\tHÆ\u0001¢\u0006\u0002\u0010.J\u0013\u0010/\u001a\u00020\u00052\b\u00100\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00101\u001a\u00020\tHÖ\u0001J\t\u00102\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u0014\u0010\u0015R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u0017\u0010\u0015R\u0018\u0010\u0007\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001b\u001a\u0004\b\u0019\u0010\u001aR\u001a\u0010\n\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u001c\u0010\u0015R\u0018\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u0013R\u001a\u0010\f\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001b\u001a\u0004\b\u001e\u0010\u001aR\u001a\u0010\r\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u001f\u0010\u0015R\u0018\u0010\u000e\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b \u0010\u0013R\u001a\u0010\u000f\u001a\u0004\u0018\u00010\t8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001b\u001a\u0004\b!\u0010\u001a¨\u00063"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/CCIRemote$Output;", "", "bandAreaBackground", "", "bandAreaDisabled", "", "cciDisabled", "cciLineColor", "cciLineWidth", "", "lowerBandDisabled", "lowerBandLineColor", "lowerBandLineWidth", "upperBandDisabled", "upperBandLineColor", "upperBandLineWidth", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getBandAreaBackground", "()Ljava/lang/String;", "getBandAreaDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getCciDisabled", "getCciLineColor", "getCciLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getLowerBandDisabled", "getLowerBandLineColor", "getLowerBandLineWidth", "getUpperBandDisabled", "getUpperBandLineColor", "getUpperBandLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/CCIRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("bandArea_background")
        private final String bandAreaBackground;

        @SerializedName("bandArea_disabled")
        private final Boolean bandAreaDisabled;

        @SerializedName("cci_disabled")
        private final Boolean cciDisabled;

        @SerializedName("cci_lineColor")
        private final String cciLineColor;

        @SerializedName("cci_lineWidth")
        private final Integer cciLineWidth;

        @SerializedName("lowerBand_disabled")
        private final Boolean lowerBandDisabled;

        @SerializedName("lowerBand_lineColor")
        private final String lowerBandLineColor;

        @SerializedName("lowerBand_lineWidth")
        private final Integer lowerBandLineWidth;

        @SerializedName("upperBand_disabled")
        private final Boolean upperBandDisabled;

        @SerializedName("upperBand_lineColor")
        private final String upperBandLineColor;

        @SerializedName("upperBand_lineWidth")
        private final Integer upperBandLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, null, 2047, null);
        }

        public Output(String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Boolean bool4, String str4, Integer num3) {
            this.bandAreaBackground = str;
            this.bandAreaDisabled = bool;
            this.cciDisabled = bool2;
            this.cciLineColor = str2;
            this.cciLineWidth = num;
            this.lowerBandDisabled = bool3;
            this.lowerBandLineColor = str3;
            this.lowerBandLineWidth = num2;
            this.upperBandDisabled = bool4;
            this.upperBandLineColor = str4;
            this.upperBandLineWidth = num3;
        }

        public /* synthetic */ Output(String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Boolean bool4, String str4, Integer num3, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, (i10 & 2) != 0 ? null : bool, (i10 & 4) != 0 ? null : bool2, (i10 & 8) != 0 ? null : str2, (i10 & 16) != 0 ? null : num, (i10 & 32) != 0 ? null : bool3, (i10 & 64) != 0 ? null : str3, (i10 & 128) != 0 ? null : num2, (i10 & 256) != 0 ? null : bool4, (i10 & 512) != 0 ? null : str4, (i10 & 1024) != 0 ? null : num3);
        }

        public static /* synthetic */ Output copy$default(Output output, String str, Boolean bool, Boolean bool2, String str2, Integer num, Boolean bool3, String str3, Integer num2, Boolean bool4, String str4, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                str = output.bandAreaBackground;
            }
            if ((i10 & 2) != 0) {
                bool = output.bandAreaDisabled;
            }
            if ((i10 & 4) != 0) {
                bool2 = output.cciDisabled;
            }
            if ((i10 & 8) != 0) {
                str2 = output.cciLineColor;
            }
            if ((i10 & 16) != 0) {
                num = output.cciLineWidth;
            }
            if ((i10 & 32) != 0) {
                bool3 = output.lowerBandDisabled;
            }
            if ((i10 & 64) != 0) {
                str3 = output.lowerBandLineColor;
            }
            if ((i10 & 128) != 0) {
                num2 = output.lowerBandLineWidth;
            }
            if ((i10 & 256) != 0) {
                bool4 = output.upperBandDisabled;
            }
            if ((i10 & 512) != 0) {
                str4 = output.upperBandLineColor;
            }
            if ((i10 & 1024) != 0) {
                num3 = output.upperBandLineWidth;
            }
            String str5 = str4;
            Integer num4 = num3;
            Integer num5 = num2;
            Boolean bool5 = bool4;
            Boolean bool6 = bool3;
            String str6 = str3;
            Integer num6 = num;
            Boolean bool7 = bool2;
            return output.copy(str, bool, bool7, str2, num6, bool6, str6, num5, bool5, str5, num4);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getBandAreaBackground() {
            return this.bandAreaBackground;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final String getUpperBandLineColor() {
            return this.upperBandLineColor;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final Integer getUpperBandLineWidth() {
            return this.upperBandLineWidth;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getBandAreaDisabled() {
            return this.bandAreaDisabled;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getCciDisabled() {
            return this.cciDisabled;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final String getCciLineColor() {
            return this.cciLineColor;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getCciLineWidth() {
            return this.cciLineWidth;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Boolean getLowerBandDisabled() {
            return this.lowerBandDisabled;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final String getLowerBandLineColor() {
            return this.lowerBandLineColor;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Integer getLowerBandLineWidth() {
            return this.lowerBandLineWidth;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Boolean getUpperBandDisabled() {
            return this.upperBandDisabled;
        }

        public final Output copy(String bandAreaBackground, Boolean bandAreaDisabled, Boolean cciDisabled, String cciLineColor, Integer cciLineWidth, Boolean lowerBandDisabled, String lowerBandLineColor, Integer lowerBandLineWidth, Boolean upperBandDisabled, String upperBandLineColor, Integer upperBandLineWidth) {
            return new Output(bandAreaBackground, bandAreaDisabled, cciDisabled, cciLineColor, cciLineWidth, lowerBandDisabled, lowerBandLineColor, lowerBandLineWidth, upperBandDisabled, upperBandLineColor, upperBandLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.bandAreaBackground, output.bandAreaBackground) && AbstractC7609s.f(this.bandAreaDisabled, output.bandAreaDisabled) && AbstractC7609s.f(this.cciDisabled, output.cciDisabled) && AbstractC7609s.f(this.cciLineColor, output.cciLineColor) && AbstractC7609s.f(this.cciLineWidth, output.cciLineWidth) && AbstractC7609s.f(this.lowerBandDisabled, output.lowerBandDisabled) && AbstractC7609s.f(this.lowerBandLineColor, output.lowerBandLineColor) && AbstractC7609s.f(this.lowerBandLineWidth, output.lowerBandLineWidth) && AbstractC7609s.f(this.upperBandDisabled, output.upperBandDisabled) && AbstractC7609s.f(this.upperBandLineColor, output.upperBandLineColor) && AbstractC7609s.f(this.upperBandLineWidth, output.upperBandLineWidth);
        }

        public final String getBandAreaBackground() {
            return this.bandAreaBackground;
        }

        public final Boolean getBandAreaDisabled() {
            return this.bandAreaDisabled;
        }

        public final Boolean getCciDisabled() {
            return this.cciDisabled;
        }

        public final String getCciLineColor() {
            return this.cciLineColor;
        }

        public final Integer getCciLineWidth() {
            return this.cciLineWidth;
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
            Boolean bool2 = this.cciDisabled;
            int iHashCode3 = (iHashCode2 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.cciLineColor;
            int iHashCode4 = (iHashCode3 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num = this.cciLineWidth;
            int iHashCode5 = (iHashCode4 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool3 = this.lowerBandDisabled;
            int iHashCode6 = (iHashCode5 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.lowerBandLineColor;
            int iHashCode7 = (iHashCode6 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num2 = this.lowerBandLineWidth;
            int iHashCode8 = (iHashCode7 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool4 = this.upperBandDisabled;
            int iHashCode9 = (iHashCode8 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            String str4 = this.upperBandLineColor;
            int iHashCode10 = (iHashCode9 + (str4 == null ? 0 : str4.hashCode())) * 31;
            Integer num3 = this.upperBandLineWidth;
            return iHashCode10 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            return "Output(bandAreaBackground=" + this.bandAreaBackground + ", bandAreaDisabled=" + this.bandAreaDisabled + ", cciDisabled=" + this.cciDisabled + ", cciLineColor=" + this.cciLineColor + ", cciLineWidth=" + this.cciLineWidth + ", lowerBandDisabled=" + this.lowerBandDisabled + ", lowerBandLineColor=" + this.lowerBandLineColor + ", lowerBandLineWidth=" + this.lowerBandLineWidth + ", upperBandDisabled=" + this.upperBandDisabled + ", upperBandLineColor=" + this.upperBandLineColor + ", upperBandLineWidth=" + this.upperBandLineWidth + ')';
        }
    }

    public CCIRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ CCIRemote copy$default(CCIRemote cCIRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = cCIRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = cCIRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = cCIRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = cCIRemote.app_input;
        }
        return cCIRemote.copy(input, output, output2, input2);
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

    public final CCIRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new CCIRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof CCIRemote)) {
            return false;
        }
        CCIRemote cCIRemote = (CCIRemote) other;
        return AbstractC7609s.f(this.input, cCIRemote.input) && AbstractC7609s.f(this.output, cCIRemote.output) && AbstractC7609s.f(this.app_output, cCIRemote.app_output) && AbstractC7609s.f(this.app_input, cCIRemote.app_input);
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
        return "CCIRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
