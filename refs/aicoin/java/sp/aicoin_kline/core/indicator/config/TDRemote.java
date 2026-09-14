package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TDRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/TDRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/TDRemote$Output;Lsp/aicoin_kline/core/indicator/config/TDRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/TDRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class TDRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0011\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\u0004\b\u0007\u0010\bJ\u0010\u0010\u000f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\nJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J2\u0010\u0012\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005HÆ\u0001¢\u0006\u0002\u0010\u0013J\u0013\u0010\u0014\u001a\u00020\u00032\b\u0010\u0015\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0016\u001a\u00020\u0017HÖ\u0001J\t\u0010\u0018\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0018\u0010\u0006\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\r¨\u0006\u0019"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/TDRemote$Output;", "", "tdHide", "", "tdNegColor", "", "tdPosColor", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;)V", "getTdHide", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getTdNegColor", "()Ljava/lang/String;", "getTdPosColor", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;)Lsp/aicoin_kline/core/indicator/config/TDRemote$Output;", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("td_hide")
        private final Boolean tdHide;

        @SerializedName("td_neg_color")
        private final String tdNegColor;

        @SerializedName("td_pos_color")
        private final String tdPosColor;

        public Output() {
            this(null, null, null, 7, null);
        }

        public Output(Boolean bool, String str, String str2) {
            this.tdHide = bool;
            this.tdNegColor = str;
            this.tdPosColor = str2;
        }

        public /* synthetic */ Output(Boolean bool, String str, String str2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : str2);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, String str2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.tdHide;
            }
            if ((i10 & 2) != 0) {
                str = output.tdNegColor;
            }
            if ((i10 & 4) != 0) {
                str2 = output.tdPosColor;
            }
            return output.copy(bool, str, str2);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getTdHide() {
            return this.tdHide;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getTdNegColor() {
            return this.tdNegColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final String getTdPosColor() {
            return this.tdPosColor;
        }

        public final Output copy(Boolean tdHide, String tdNegColor, String tdPosColor) {
            return new Output(tdHide, tdNegColor, tdPosColor);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.tdHide, output.tdHide) && AbstractC7609s.f(this.tdNegColor, output.tdNegColor) && AbstractC7609s.f(this.tdPosColor, output.tdPosColor);
        }

        public final Boolean getTdHide() {
            return this.tdHide;
        }

        public final String getTdNegColor() {
            return this.tdNegColor;
        }

        public final String getTdPosColor() {
            return this.tdPosColor;
        }

        public int hashCode() {
            Boolean bool = this.tdHide;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.tdNegColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            String str2 = this.tdPosColor;
            return iHashCode2 + (str2 != null ? str2.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(tdHide=");
            sb2.append(this.tdHide);
            sb2.append(", tdNegColor=");
            sb2.append(this.tdNegColor);
            sb2.append(", tdPosColor=");
            return kk.h.a(sb2, this.tdPosColor, ')');
        }
    }

    public TDRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ TDRemote copy$default(TDRemote tDRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = tDRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = tDRemote.app_output;
        }
        return tDRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final TDRemote copy(Output output, Output app_output) {
        return new TDRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof TDRemote)) {
            return false;
        }
        TDRemote tDRemote = (TDRemote) other;
        return AbstractC7609s.f(this.output, tDRemote.output) && AbstractC7609s.f(this.app_output, tDRemote.app_output);
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
        return "TDRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
