package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/FundFlowRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/FundFlowRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/FundFlowRemote$Output;Lsp/aicoin_kline/core/indicator/config/FundFlowRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/FundFlowRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class FundFlowRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0006\n\u0002\u0010\b\n\u0002\b\u001e\b\u0087\b\u0018\u00002\u00020\u0001Bg\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\f¢\u0006\u0004\b\r\u0010\u000eJ\u0010\u0010\u001c\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0010J\u000b\u0010\u001d\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0010J\u000b\u0010\u001f\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010 \u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0010J\u0010\u0010!\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0010J\u000b\u0010\"\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010#\u001a\u0004\u0018\u00010\fHÆ\u0003¢\u0006\u0002\u0010\u001aJn\u0010$\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\fHÆ\u0001¢\u0006\u0002\u0010%J\u0013\u0010&\u001a\u00020\u00032\b\u0010'\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010(\u001a\u00020\fHÖ\u0001J\t\u0010)\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010R\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u0014\u0010\u0010R\u0018\u0010\u0007\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u0016\u0010\u0010R\u001a\u0010\t\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u0017\u0010\u0010R\u0018\u0010\n\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0013R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\f8\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u001b\u001a\u0004\b\u0019\u0010\u001a¨\u0006*"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/FundFlowRemote$Output;", "", "fundflowDisabled", "", "fundflowNegColor", "", "fundflowNegFill", "fundflowPosColor", "fundflowPosFill", "zeroBandDisabled", "zeroBandLineColor", "zeroBandLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getFundflowDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getFundflowNegColor", "()Ljava/lang/String;", "getFundflowNegFill", "getFundflowPosColor", "getFundflowPosFill", "getZeroBandDisabled", "getZeroBandLineColor", "getZeroBandLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/FundFlowRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("fundflow_disabled")
        private final Boolean fundflowDisabled;

        @SerializedName("fundflow_neg_color")
        private final String fundflowNegColor;

        @SerializedName("fundflow_neg_fill")
        private final Boolean fundflowNegFill;

        @SerializedName("fundflow_pos_color")
        private final String fundflowPosColor;

        @SerializedName("fundflow_pos_fill")
        private final Boolean fundflowPosFill;

        @SerializedName("zeroBand_disabled")
        private final Boolean zeroBandDisabled;

        @SerializedName("zeroBand_lineColor")
        private final String zeroBandLineColor;

        @SerializedName("zeroBand_lineWidth")
        private final Integer zeroBandLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, 255, null);
        }

        public Output(Boolean bool, String str, Boolean bool2, String str2, Boolean bool3, Boolean bool4, String str3, Integer num) {
            this.fundflowDisabled = bool;
            this.fundflowNegColor = str;
            this.fundflowNegFill = bool2;
            this.fundflowPosColor = str2;
            this.fundflowPosFill = bool3;
            this.zeroBandDisabled = bool4;
            this.zeroBandLineColor = str3;
            this.zeroBandLineWidth = num;
        }

        public /* synthetic */ Output(Boolean bool, String str, Boolean bool2, String str2, Boolean bool3, Boolean bool4, String str3, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : bool2, (i10 & 8) != 0 ? null : str2, (i10 & 16) != 0 ? null : bool3, (i10 & 32) != 0 ? null : bool4, (i10 & 64) != 0 ? null : str3, (i10 & 128) != 0 ? null : num);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Boolean bool2, String str2, Boolean bool3, Boolean bool4, String str3, Integer num, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.fundflowDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.fundflowNegColor;
            }
            if ((i10 & 4) != 0) {
                bool2 = output.fundflowNegFill;
            }
            if ((i10 & 8) != 0) {
                str2 = output.fundflowPosColor;
            }
            if ((i10 & 16) != 0) {
                bool3 = output.fundflowPosFill;
            }
            if ((i10 & 32) != 0) {
                bool4 = output.zeroBandDisabled;
            }
            if ((i10 & 64) != 0) {
                str3 = output.zeroBandLineColor;
            }
            if ((i10 & 128) != 0) {
                num = output.zeroBandLineWidth;
            }
            String str4 = str3;
            Integer num2 = num;
            Boolean bool5 = bool3;
            Boolean bool6 = bool4;
            return output.copy(bool, str, bool2, str2, bool5, bool6, str4, num2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getFundflowDisabled() {
            return this.fundflowDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getFundflowNegColor() {
            return this.fundflowNegColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getFundflowNegFill() {
            return this.fundflowNegFill;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final String getFundflowPosColor() {
            return this.fundflowPosColor;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Boolean getFundflowPosFill() {
            return this.fundflowPosFill;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Boolean getZeroBandDisabled() {
            return this.zeroBandDisabled;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final String getZeroBandLineColor() {
            return this.zeroBandLineColor;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Integer getZeroBandLineWidth() {
            return this.zeroBandLineWidth;
        }

        public final Output copy(Boolean fundflowDisabled, String fundflowNegColor, Boolean fundflowNegFill, String fundflowPosColor, Boolean fundflowPosFill, Boolean zeroBandDisabled, String zeroBandLineColor, Integer zeroBandLineWidth) {
            return new Output(fundflowDisabled, fundflowNegColor, fundflowNegFill, fundflowPosColor, fundflowPosFill, zeroBandDisabled, zeroBandLineColor, zeroBandLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.fundflowDisabled, output.fundflowDisabled) && AbstractC7609s.f(this.fundflowNegColor, output.fundflowNegColor) && AbstractC7609s.f(this.fundflowNegFill, output.fundflowNegFill) && AbstractC7609s.f(this.fundflowPosColor, output.fundflowPosColor) && AbstractC7609s.f(this.fundflowPosFill, output.fundflowPosFill) && AbstractC7609s.f(this.zeroBandDisabled, output.zeroBandDisabled) && AbstractC7609s.f(this.zeroBandLineColor, output.zeroBandLineColor) && AbstractC7609s.f(this.zeroBandLineWidth, output.zeroBandLineWidth);
        }

        public final Boolean getFundflowDisabled() {
            return this.fundflowDisabled;
        }

        public final String getFundflowNegColor() {
            return this.fundflowNegColor;
        }

        public final Boolean getFundflowNegFill() {
            return this.fundflowNegFill;
        }

        public final String getFundflowPosColor() {
            return this.fundflowPosColor;
        }

        public final Boolean getFundflowPosFill() {
            return this.fundflowPosFill;
        }

        public final Boolean getZeroBandDisabled() {
            return this.zeroBandDisabled;
        }

        public final String getZeroBandLineColor() {
            return this.zeroBandLineColor;
        }

        public final Integer getZeroBandLineWidth() {
            return this.zeroBandLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.fundflowDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.fundflowNegColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Boolean bool2 = this.fundflowNegFill;
            int iHashCode3 = (iHashCode2 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.fundflowPosColor;
            int iHashCode4 = (iHashCode3 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Boolean bool3 = this.fundflowPosFill;
            int iHashCode5 = (iHashCode4 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            Boolean bool4 = this.zeroBandDisabled;
            int iHashCode6 = (iHashCode5 + (bool4 == null ? 0 : bool4.hashCode())) * 31;
            String str3 = this.zeroBandLineColor;
            int iHashCode7 = (iHashCode6 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num = this.zeroBandLineWidth;
            return iHashCode7 + (num != null ? num.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(fundflowDisabled=");
            sb2.append(this.fundflowDisabled);
            sb2.append(", fundflowNegColor=");
            sb2.append(this.fundflowNegColor);
            sb2.append(", fundflowNegFill=");
            sb2.append(this.fundflowNegFill);
            sb2.append(", fundflowPosColor=");
            sb2.append(this.fundflowPosColor);
            sb2.append(", fundflowPosFill=");
            sb2.append(this.fundflowPosFill);
            sb2.append(", zeroBandDisabled=");
            sb2.append(this.zeroBandDisabled);
            sb2.append(", zeroBandLineColor=");
            sb2.append(this.zeroBandLineColor);
            sb2.append(", zeroBandLineWidth=");
            return kk.b.a(sb2, this.zeroBandLineWidth, ')');
        }
    }

    public FundFlowRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ FundFlowRemote copy$default(FundFlowRemote fundFlowRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = fundFlowRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = fundFlowRemote.app_output;
        }
        return fundFlowRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final FundFlowRemote copy(Output output, Output app_output) {
        return new FundFlowRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof FundFlowRemote)) {
            return false;
        }
        FundFlowRemote fundFlowRemote = (FundFlowRemote) other;
        return AbstractC7609s.f(this.output, fundFlowRemote.output) && AbstractC7609s.f(this.app_output, fundFlowRemote.app_output);
    }

    public final Output getApp_output() {
        return this.app_output;
    }

    public final Output getOutput() {
        return this.output;
    }

    public int hashCode() {
        Output output = this.output;
        int iHashCode = (output == null ? 0 : output.hashCode()) * 31;
        Output output2 = this.app_output;
        return iHashCode + (output2 != null ? output2.hashCode() : 0);
    }

    public String toString() {
        return "FundFlowRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
