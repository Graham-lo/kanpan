package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VPVRRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Input;Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Output;Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Output;Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class VPVRRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u000f\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B%\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0006\u0010\u0007J\u0010\u0010\r\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ\u0010\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\tJ2\u0010\u0010\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u0011J\u0013\u0010\u0012\u001a\u00020\u00132\b\u0010\u0014\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\b\u0010\tR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\u000b\u0010\tR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\n\u001a\u0004\b\f\u0010\t¨\u0006\u0018"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Input;", "", "range1", "", "range2", "rows", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getRange1", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getRange2", "getRows", "component1", "component2", "component3", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer range1;
        private final Integer range2;
        private final Integer rows;

        public Input(Integer num, Integer num2, Integer num3) {
            this.range1 = num;
            this.range2 = num2;
            this.rows = num3;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.range1;
            }
            if ((i10 & 2) != 0) {
                num2 = input.range2;
            }
            if ((i10 & 4) != 0) {
                num3 = input.rows;
            }
            return input.copy(num, num2, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getRange1() {
            return this.range1;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getRange2() {
            return this.range2;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getRows() {
            return this.rows;
        }

        public final Input copy(Integer range1, Integer range2, Integer rows) {
            return new Input(range1, range2, rows);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.range1, input.range1) && AbstractC7609s.f(this.range2, input.range2) && AbstractC7609s.f(this.rows, input.rows);
        }

        public final Integer getRange1() {
            return this.range1;
        }

        public final Integer getRange2() {
            return this.range2;
        }

        public final Integer getRows() {
            return this.rows;
        }

        public int hashCode() {
            Integer num = this.range1;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.range2;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.rows;
            return iHashCode2 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(range1=");
            sb2.append(this.range1);
            sb2.append(", range2=");
            sb2.append(this.range2);
            sb2.append(", rows=");
            return kk.b.a(sb2, this.rows, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b,\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B\u0097\u0001\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0010\u0010\u0011J\u000b\u0010!\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010\"\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u000b\u0010#\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010$\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010%\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010&\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010'\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u0010\u0010(\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u000b\u0010)\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010*\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0015J\u000b\u0010+\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010,\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u009e\u0001\u0010-\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010.J\u0013\u0010/\u001a\u00020\u00052\b\u00100\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00101\u001a\u000202HÖ\u0001J\t\u00103\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u0014\u0010\u0015R\u0018\u0010\u0006\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0017\u0010\u0013R\u0018\u0010\u0007\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0013R\u0018\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0013R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u0013R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u001b\u0010\u0015R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u001c\u0010\u0015R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u0013R\u001a\u0010\r\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0016\u001a\u0004\b\u001e\u0010\u0015R\u0018\u0010\u000e\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010\u0013R\u0018\u0010\u000f\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b \u0010\u0013¨\u00064"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Output;", "", "pocColor", "", "range2Disabled", "", "range2NegFill", "range2PosFill", "range1NegFill", "range1PosFill", "range1Disabled", "vpIsOnRight", "vpLabelFill", "pocDisabled", "vpNegFill", "vpPosFill", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;)V", "getPocColor", "()Ljava/lang/String;", "getRange2Disabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getRange2NegFill", "getRange2PosFill", "getRange1NegFill", "getRange1PosFill", "getRange1Disabled", "getVpIsOnRight", "getVpLabelFill", "getPocDisabled", "getVpNegFill", "getVpPosFill", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;)Lsp/aicoin_kline/core/indicator/config/VPVRRemote$Output;", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("poc_color")
        private final String pocColor;

        @SerializedName("poc_disabled")
        private final Boolean pocDisabled;

        @SerializedName("range1_disabled")
        private final Boolean range1Disabled;

        @SerializedName("range1_negFill")
        private final String range1NegFill;

        @SerializedName("range1_posFill")
        private final String range1PosFill;

        @SerializedName("range2_disabled")
        private final Boolean range2Disabled;

        @SerializedName("range2_negFill")
        private final String range2NegFill;

        @SerializedName("range2_posFill")
        private final String range2PosFill;

        @SerializedName("vp_isOnRight")
        private final Boolean vpIsOnRight;

        @SerializedName("vp_labelFill")
        private final String vpLabelFill;

        @SerializedName("vp_negFill")
        private final String vpNegFill;

        @SerializedName("vp_posFill")
        private final String vpPosFill;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
        }

        public Output(String str, Boolean bool, String str2, String str3, String str4, String str5, Boolean bool2, Boolean bool3, String str6, Boolean bool4, String str7, String str8) {
            this.pocColor = str;
            this.range2Disabled = bool;
            this.range2NegFill = str2;
            this.range2PosFill = str3;
            this.range1NegFill = str4;
            this.range1PosFill = str5;
            this.range1Disabled = bool2;
            this.vpIsOnRight = bool3;
            this.vpLabelFill = str6;
            this.pocDisabled = bool4;
            this.vpNegFill = str7;
            this.vpPosFill = str8;
        }

        public /* synthetic */ Output(String str, Boolean bool, String str2, String str3, String str4, String str5, Boolean bool2, Boolean bool3, String str6, Boolean bool4, String str7, String str8, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, (i10 & 2) != 0 ? Boolean.FALSE : bool, (i10 & 4) != 0 ? null : str2, (i10 & 8) != 0 ? null : str3, (i10 & 16) != 0 ? null : str4, (i10 & 32) != 0 ? null : str5, (i10 & 64) != 0 ? Boolean.FALSE : bool2, (i10 & 128) != 0 ? Boolean.FALSE : bool3, (i10 & 256) != 0 ? null : str6, (i10 & 512) != 0 ? Boolean.FALSE : bool4, (i10 & 1024) != 0 ? null : str7, (i10 & 2048) != 0 ? null : str8);
        }

        public static /* synthetic */ Output copy$default(Output output, String str, Boolean bool, String str2, String str3, String str4, String str5, Boolean bool2, Boolean bool3, String str6, Boolean bool4, String str7, String str8, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                str = output.pocColor;
            }
            if ((i10 & 2) != 0) {
                bool = output.range2Disabled;
            }
            if ((i10 & 4) != 0) {
                str2 = output.range2NegFill;
            }
            if ((i10 & 8) != 0) {
                str3 = output.range2PosFill;
            }
            if ((i10 & 16) != 0) {
                str4 = output.range1NegFill;
            }
            if ((i10 & 32) != 0) {
                str5 = output.range1PosFill;
            }
            if ((i10 & 64) != 0) {
                bool2 = output.range1Disabled;
            }
            if ((i10 & 128) != 0) {
                bool3 = output.vpIsOnRight;
            }
            if ((i10 & 256) != 0) {
                str6 = output.vpLabelFill;
            }
            if ((i10 & 512) != 0) {
                bool4 = output.pocDisabled;
            }
            if ((i10 & 1024) != 0) {
                str7 = output.vpNegFill;
            }
            if ((i10 & 2048) != 0) {
                str8 = output.vpPosFill;
            }
            String str9 = str7;
            String str10 = str8;
            String str11 = str6;
            Boolean bool5 = bool4;
            Boolean bool6 = bool2;
            Boolean bool7 = bool3;
            String str12 = str4;
            String str13 = str5;
            return output.copy(str, bool, str2, str3, str12, str13, bool6, bool7, str11, bool5, str9, str10);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getPocColor() {
            return this.pocColor;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final Boolean getPocDisabled() {
            return this.pocDisabled;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final String getVpNegFill() {
            return this.vpNegFill;
        }

        /* JADX INFO: renamed from: component12, reason: from getter */
        public final String getVpPosFill() {
            return this.vpPosFill;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getRange2Disabled() {
            return this.range2Disabled;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final String getRange2NegFill() {
            return this.range2NegFill;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final String getRange2PosFill() {
            return this.range2PosFill;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getRange1NegFill() {
            return this.range1NegFill;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final String getRange1PosFill() {
            return this.range1PosFill;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getRange1Disabled() {
            return this.range1Disabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Boolean getVpIsOnRight() {
            return this.vpIsOnRight;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final String getVpLabelFill() {
            return this.vpLabelFill;
        }

        public final Output copy(String pocColor, Boolean range2Disabled, String range2NegFill, String range2PosFill, String range1NegFill, String range1PosFill, Boolean range1Disabled, Boolean vpIsOnRight, String vpLabelFill, Boolean pocDisabled, String vpNegFill, String vpPosFill) {
            return new Output(pocColor, range2Disabled, range2NegFill, range2PosFill, range1NegFill, range1PosFill, range1Disabled, vpIsOnRight, vpLabelFill, pocDisabled, vpNegFill, vpPosFill);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.pocColor, output.pocColor) && AbstractC7609s.f(this.range2Disabled, output.range2Disabled) && AbstractC7609s.f(this.range2NegFill, output.range2NegFill) && AbstractC7609s.f(this.range2PosFill, output.range2PosFill) && AbstractC7609s.f(this.range1NegFill, output.range1NegFill) && AbstractC7609s.f(this.range1PosFill, output.range1PosFill) && AbstractC7609s.f(this.range1Disabled, output.range1Disabled) && AbstractC7609s.f(this.vpIsOnRight, output.vpIsOnRight) && AbstractC7609s.f(this.vpLabelFill, output.vpLabelFill) && AbstractC7609s.f(this.pocDisabled, output.pocDisabled) && AbstractC7609s.f(this.vpNegFill, output.vpNegFill) && AbstractC7609s.f(this.vpPosFill, output.vpPosFill);
        }

        public final String getPocColor() {
            return this.pocColor;
        }

        public final Boolean getPocDisabled() {
            return this.pocDisabled;
        }

        public final Boolean getRange1Disabled() {
            return this.range1Disabled;
        }

        public final String getRange1NegFill() {
            return this.range1NegFill;
        }

        public final String getRange1PosFill() {
            return this.range1PosFill;
        }

        public final Boolean getRange2Disabled() {
            return this.range2Disabled;
        }

        public final String getRange2NegFill() {
            return this.range2NegFill;
        }

        public final String getRange2PosFill() {
            return this.range2PosFill;
        }

        public final Boolean getVpIsOnRight() {
            return this.vpIsOnRight;
        }

        public final String getVpLabelFill() {
            return this.vpLabelFill;
        }

        public final String getVpNegFill() {
            return this.vpNegFill;
        }

        public final String getVpPosFill() {
            return this.vpPosFill;
        }

        public int hashCode() {
            String str = this.pocColor;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            Boolean bool = this.range2Disabled;
            int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
            String str2 = this.range2NegFill;
            int iHashCode3 = (iHashCode2 + (str2 == null ? 0 : str2.hashCode())) * 31;
            String str3 = this.range2PosFill;
            int iHashCode4 = (iHashCode3 + (str3 == null ? 0 : str3.hashCode())) * 31;
            String str4 = this.range1NegFill;
            int iHashCode5 = (iHashCode4 + (str4 == null ? 0 : str4.hashCode())) * 31;
            String str5 = this.range1PosFill;
            int iHashCode6 = (iHashCode5 + (str5 == null ? 0 : str5.hashCode())) * 31;
            Boolean bool2 = this.range1Disabled;
            int iHashCode7 = (iHashCode6 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            Boolean bool3 = this.vpIsOnRight;
            int iHashCode8 = (iHashCode7 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str6 = this.vpLabelFill;
            int iHashCode9 = (iHashCode8 + (str6 == null ? 0 : str6.hashCode())) * 31;
            Boolean bool4 = this.pocDisabled;
            int iHashCode10 = (iHashCode9 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            String str7 = this.vpNegFill;
            int iHashCode11 = (iHashCode10 + (str7 == null ? 0 : str7.hashCode())) * 31;
            String str8 = this.vpPosFill;
            return iHashCode11 + (str8 != null ? str8.hashCode() : 0);
        }

        public String toString() {
            return "Output(pocColor=" + this.pocColor + ", range2Disabled=" + this.range2Disabled + ", range2NegFill=" + this.range2NegFill + ", range2PosFill=" + this.range2PosFill + ", range1NegFill=" + this.range1NegFill + ", range1PosFill=" + this.range1PosFill + ", range1Disabled=" + this.range1Disabled + ", vpIsOnRight=" + this.vpIsOnRight + ", vpLabelFill=" + this.vpLabelFill + ", pocDisabled=" + this.pocDisabled + ", vpNegFill=" + this.vpNegFill + ", vpPosFill=" + this.vpPosFill + ')';
        }
    }

    public VPVRRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ VPVRRemote copy$default(VPVRRemote vPVRRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = vPVRRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = vPVRRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = vPVRRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = vPVRRemote.app_input;
        }
        return vPVRRemote.copy(input, output, output2, input2);
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

    public final VPVRRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new VPVRRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof VPVRRemote)) {
            return false;
        }
        VPVRRemote vPVRRemote = (VPVRRemote) other;
        return AbstractC7609s.f(this.input, vPVRRemote.input) && AbstractC7609s.f(this.output, vPVRRemote.output) && AbstractC7609s.f(this.app_output, vPVRRemote.app_output) && AbstractC7609s.f(this.app_input, vPVRRemote.app_input);
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
        return "VPVRRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
