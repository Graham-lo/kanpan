package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TTMURemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/TTMURemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/TTMURemote$Output;Lsp/aicoin_kline/core/indicator/config/TTMURemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/TTMURemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class TTMURemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u001d\b\u0087\b\u0018\u00002\u00020\u0001BO\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000b\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u0019\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001a\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013J\u0010\u0010\u001b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000eJ\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0013JV\u0010\u001e\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u001fJ\u0013\u0010 \u001a\u00020\u00032\b\u0010!\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\"\u001a\u00020\u0007HÖ\u0001J\t\u0010#\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\r\u0010\u000eR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0012\u0010\u0013R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000f\u001a\u0004\b\u0015\u0010\u000eR\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0011R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0017\u0010\u0013¨\u0006$"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TTMURemote$Output;", "", "longDisabled", "", "longLineColor", "", "longLineWidth", "", "shortDisabled", "shortLineColor", "shortLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getLongDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getLongLineColor", "()Ljava/lang/String;", "getLongLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getShortDisabled", "getShortLineColor", "getShortLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/TTMURemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("long_disabled")
        private final Boolean longDisabled;

        @SerializedName("long_lineColor")
        private final String longLineColor;

        @SerializedName("long_lineWidth")
        private final Integer longLineWidth;

        @SerializedName("short_disabled")
        private final Boolean shortDisabled;

        @SerializedName("short_lineColor")
        private final String shortLineColor;

        @SerializedName("short_lineWidth")
        private final Integer shortLineWidth;

        public Output() {
            this(null, null, null, null, null, null, 63, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2) {
            this.longDisabled = bool;
            this.longLineColor = str;
            this.longLineWidth = num;
            this.shortDisabled = bool2;
            this.shortLineColor = str2;
            this.shortLineWidth = num2;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.longDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.longLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.longLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.shortDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.shortLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.shortLineWidth;
            }
            String str3 = str2;
            Integer num3 = num2;
            return output.copy(bool, str, num, bool2, str3, num3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getLongDisabled() {
            return this.longDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getLongLineColor() {
            return this.longLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getLongLineWidth() {
            return this.longLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getShortDisabled() {
            return this.shortDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getShortLineColor() {
            return this.shortLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getShortLineWidth() {
            return this.shortLineWidth;
        }

        public final Output copy(Boolean longDisabled, String longLineColor, Integer longLineWidth, Boolean shortDisabled, String shortLineColor, Integer shortLineWidth) {
            return new Output(longDisabled, longLineColor, longLineWidth, shortDisabled, shortLineColor, shortLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.longDisabled, output.longDisabled) && AbstractC7609s.f(this.longLineColor, output.longLineColor) && AbstractC7609s.f(this.longLineWidth, output.longLineWidth) && AbstractC7609s.f(this.shortDisabled, output.shortDisabled) && AbstractC7609s.f(this.shortLineColor, output.shortLineColor) && AbstractC7609s.f(this.shortLineWidth, output.shortLineWidth);
        }

        public final Boolean getLongDisabled() {
            return this.longDisabled;
        }

        public final String getLongLineColor() {
            return this.longLineColor;
        }

        public final Integer getLongLineWidth() {
            return this.longLineWidth;
        }

        public final Boolean getShortDisabled() {
            return this.shortDisabled;
        }

        public final String getShortLineColor() {
            return this.shortLineColor;
        }

        public final Integer getShortLineWidth() {
            return this.shortLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.longDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.longLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.longLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.shortDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.shortLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.shortLineWidth;
            return iHashCode5 + (num2 != null ? num2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(longDisabled=");
            sb2.append(this.longDisabled);
            sb2.append(", longLineColor=");
            sb2.append(this.longLineColor);
            sb2.append(", longLineWidth=");
            sb2.append(this.longLineWidth);
            sb2.append(", shortDisabled=");
            sb2.append(this.shortDisabled);
            sb2.append(", shortLineColor=");
            sb2.append(this.shortLineColor);
            sb2.append(", shortLineWidth=");
            return kk.b.a(sb2, this.shortLineWidth, ')');
        }
    }

    public TTMURemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ TTMURemote copy$default(TTMURemote tTMURemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = tTMURemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = tTMURemote.app_output;
        }
        return tTMURemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final TTMURemote copy(Output output, Output app_output) {
        return new TTMURemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof TTMURemote)) {
            return false;
        }
        TTMURemote tTMURemote = (TTMURemote) other;
        return AbstractC7609s.f(this.output, tTMURemote.output) && AbstractC7609s.f(this.app_output, tTMURemote.app_output);
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
        return "TTMURemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
