package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001d\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/FRRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/FRRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/FRRemote$Output;Lsp/aicoin_kline/core/indicator/config/FRRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/FRRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class FRRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u001d\b\u0087\b\u0018\u00002\u00020\u0001BO\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000b\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u0019\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001a\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013J\u0010\u0010\u001b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013JV\u0010\u001e\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u001fJ\u0013\u0010 \u001a\u00020\u00032\b\u0010!\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\"\u001a\u00020\u0007HÖ\u0001J\t\u0010#\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\r\u0010\u000eR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\u0015\u0010\u000eR\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0011R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0017\u0010\u0013¨\u0006$"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/FRRemote$Output;", "", "frDisabled", "", "frLineColor", "", "frLineWidth", "", "zeroBandDisabled", "zeroBandLineColor", "zeroBandLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getFrDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getFrLineColor", "()Ljava/lang/String;", "getFrLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getZeroBandDisabled", "getZeroBandLineColor", "getZeroBandLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/FRRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("fr_disabled")
        private final Boolean frDisabled;

        @SerializedName("fr_lineColor")
        private final String frLineColor;

        @SerializedName("fr_lineWidth")
        private final Integer frLineWidth;

        @SerializedName("zeroBand_disabled")
        private final Boolean zeroBandDisabled;

        @SerializedName("zeroBand_lineColor")
        private final String zeroBandLineColor;

        @SerializedName("zeroBand_lineWidth")
        private final Integer zeroBandLineWidth;

        public Output() {
            this(null, null, null, null, null, null, 63, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2) {
            this.frDisabled = bool;
            this.frLineColor = str;
            this.frLineWidth = num;
            this.zeroBandDisabled = bool2;
            this.zeroBandLineColor = str2;
            this.zeroBandLineWidth = num2;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.frDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.frLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.frLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.zeroBandDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.zeroBandLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.zeroBandLineWidth;
            }
            String str3 = str2;
            Integer num3 = num2;
            return output.copy(bool, str, num, bool2, str3, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getFrDisabled() {
            return this.frDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getFrLineColor() {
            return this.frLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getFrLineWidth() {
            return this.frLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getZeroBandDisabled() {
            return this.zeroBandDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getZeroBandLineColor() {
            return this.zeroBandLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getZeroBandLineWidth() {
            return this.zeroBandLineWidth;
        }

        public final Output copy(Boolean frDisabled, String frLineColor, Integer frLineWidth, Boolean zeroBandDisabled, String zeroBandLineColor, Integer zeroBandLineWidth) {
            return new Output(frDisabled, frLineColor, frLineWidth, zeroBandDisabled, zeroBandLineColor, zeroBandLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.frDisabled, output.frDisabled) && AbstractC7609s.f(this.frLineColor, output.frLineColor) && AbstractC7609s.f(this.frLineWidth, output.frLineWidth) && AbstractC7609s.f(this.zeroBandDisabled, output.zeroBandDisabled) && AbstractC7609s.f(this.zeroBandLineColor, output.zeroBandLineColor) && AbstractC7609s.f(this.zeroBandLineWidth, output.zeroBandLineWidth);
        }

        public final Boolean getFrDisabled() {
            return this.frDisabled;
        }

        public final String getFrLineColor() {
            return this.frLineColor;
        }

        public final Integer getFrLineWidth() {
            return this.frLineWidth;
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
            Boolean bool = this.frDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.frLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.frLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.zeroBandDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.zeroBandLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.zeroBandLineWidth;
            return iHashCode5 + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(frDisabled=");
            sb2.append(this.frDisabled);
            sb2.append(", frLineColor=");
            sb2.append(this.frLineColor);
            sb2.append(", frLineWidth=");
            sb2.append(this.frLineWidth);
            sb2.append(", zeroBandDisabled=");
            sb2.append(this.zeroBandDisabled);
            sb2.append(", zeroBandLineColor=");
            sb2.append(this.zeroBandLineColor);
            sb2.append(", zeroBandLineWidth=");
            return kk.b.a(sb2, this.zeroBandLineWidth, ')');
        }
    }

    public FRRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public /* synthetic */ FRRemote(Output output, Output output2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? null : output, output2);
    }

    public static /* synthetic */ FRRemote copy$default(FRRemote fRRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = fRRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = fRRemote.app_output;
        }
        return fRRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final FRRemote copy(Output output, Output app_output) {
        return new FRRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof FRRemote)) {
            return false;
        }
        FRRemote fRRemote = (FRRemote) other;
        return AbstractC7609s.f(this.output, fRRemote.output) && AbstractC7609s.f(this.app_output, fRRemote.app_output);
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
        return "FRRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
