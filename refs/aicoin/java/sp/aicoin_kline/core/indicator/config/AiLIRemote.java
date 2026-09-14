package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\u0014B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u000b\u0010\n\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J!\u0010\f\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\r\u001a\u00020\u000e2\b\u0010\u000f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0010\u001a\u00020\u0011HÖ\u0001J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AiLIRemote;", "", "output", "Lsp/aicoin_kline/core/indicator/config/AiLIRemote$Output;", "app_output", "<init>", "(Lsp/aicoin_kline/core/indicator/config/AiLIRemote$Output;Lsp/aicoin_kline/core/indicator/config/AiLIRemote$Output;)V", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/AiLIRemote$Output;", "getApp_output", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AiLIRemote {
    private final Output app_output;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u001a\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001BO\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005¢\u0006\u0004\b\n\u0010\u000bJ\u000b\u0010\u0015\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010\u0016\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u000fJ\u0010\u0010\u0017\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u000fJ\u000b\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010\u0019\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u000fJ\u0010\u0010\u001a\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u000fJV\u0010\u001b\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005HÆ\u0001¢\u0006\u0002\u0010\u001cJ\u0013\u0010\u001d\u001a\u00020\u00052\b\u0010\u001e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001f\u001a\u00020 HÖ\u0001J\t\u0010!\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0010\u001a\u0004\b\u000e\u0010\u000fR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0010\u001a\u0004\b\u0011\u0010\u000fR\u0018\u0010\u0007\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\rR\u001a\u0010\b\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0010\u001a\u0004\b\u0013\u0010\u000fR\u001a\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0010\u001a\u0004\b\u0014\u0010\u000f¨\u0006\""}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AiLIRemote$Output;", "", "negColor", "", "negDisabled", "", "negFill", "posColor", "posDisabled", "posFill", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)V", "getNegColor", "()Ljava/lang/String;", "getNegDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getNegFill", "getPosColor", "getPosDisabled", "getPosFill", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/AiLIRemote$Output;", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("neg_color")
        private final String negColor;

        @SerializedName("neg_disabled")
        private final Boolean negDisabled;

        @SerializedName("neg_fill")
        private final Boolean negFill;

        @SerializedName("pos_color")
        private final String posColor;

        @SerializedName("pos_disabled")
        private final Boolean posDisabled;

        @SerializedName("pos_fill")
        private final Boolean posFill;

        public Output() {
            this(null, null, null, null, null, null, 63, null);
        }

        public Output(String str, Boolean bool, Boolean bool2, String str2, Boolean bool3, Boolean bool4) {
            this.negColor = str;
            this.negDisabled = bool;
            this.negFill = bool2;
            this.posColor = str2;
            this.posDisabled = bool3;
            this.posFill = bool4;
        }

        public /* synthetic */ Output(String str, Boolean bool, Boolean bool2, String str2, Boolean bool3, Boolean bool4, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, (i10 & 2) != 0 ? null : bool, (i10 & 4) != 0 ? null : bool2, (i10 & 8) != 0 ? null : str2, (i10 & 16) != 0 ? null : bool3, (i10 & 32) != 0 ? null : bool4);
        }

        public static /* synthetic */ Output copy$default(Output output, String str, Boolean bool, Boolean bool2, String str2, Boolean bool3, Boolean bool4, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                str = output.negColor;
            }
            if ((i10 & 2) != 0) {
                bool = output.negDisabled;
            }
            if ((i10 & 4) != 0) {
                bool2 = output.negFill;
            }
            if ((i10 & 8) != 0) {
                str2 = output.posColor;
            }
            if ((i10 & 16) != 0) {
                bool3 = output.posDisabled;
            }
            if ((i10 & 32) != 0) {
                bool4 = output.posFill;
            }
            Boolean bool5 = bool3;
            Boolean bool6 = bool4;
            return output.copy(str, bool, bool2, str2, bool5, bool6);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getNegColor() {
            return this.negColor;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getNegDisabled() {
            return this.negDisabled;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Boolean getNegFill() {
            return this.negFill;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final String getPosColor() {
            return this.posColor;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Boolean getPosDisabled() {
            return this.posDisabled;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Boolean getPosFill() {
            return this.posFill;
        }

        public final Output copy(String negColor, Boolean negDisabled, Boolean negFill, String posColor, Boolean posDisabled, Boolean posFill) {
            return new Output(negColor, negDisabled, negFill, posColor, posDisabled, posFill);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.negColor, output.negColor) && AbstractC7609s.f(this.negDisabled, output.negDisabled) && AbstractC7609s.f(this.negFill, output.negFill) && AbstractC7609s.f(this.posColor, output.posColor) && AbstractC7609s.f(this.posDisabled, output.posDisabled) && AbstractC7609s.f(this.posFill, output.posFill);
        }

        public final String getNegColor() {
            return this.negColor;
        }

        public final Boolean getNegDisabled() {
            return this.negDisabled;
        }

        public final Boolean getNegFill() {
            return this.negFill;
        }

        public final String getPosColor() {
            return this.posColor;
        }

        public final Boolean getPosDisabled() {
            return this.posDisabled;
        }

        public final Boolean getPosFill() {
            return this.posFill;
        }

        public int hashCode() {
            String str = this.negColor;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            Boolean bool = this.negDisabled;
            int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
            Boolean bool2 = this.negFill;
            int iHashCode3 = (iHashCode2 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.posColor;
            int iHashCode4 = (iHashCode3 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Boolean bool3 = this.posDisabled;
            int iHashCode5 = (iHashCode4 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            Boolean bool4 = this.posFill;
            return iHashCode5 + (bool4 != null ? bool4.hashCode() : 0);
        }

        public String toString() {
            return "Output(negColor=" + this.negColor + ", negDisabled=" + this.negDisabled + ", negFill=" + this.negFill + ", posColor=" + this.posColor + ", posDisabled=" + this.posDisabled + ", posFill=" + this.posFill + ')';
        }
    }

    public AiLIRemote(Output output, Output output2) {
        this.output = output;
        this.app_output = output2;
    }

    public static /* synthetic */ AiLIRemote copy$default(AiLIRemote aiLIRemote, Output output, Output output2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            output = aiLIRemote.output;
        }
        if ((i10 & 2) != 0) {
            output2 = aiLIRemote.app_output;
        }
        return aiLIRemote.copy(output, output2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final Output getOutput() {
        return this.output;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final Output getApp_output() {
        return this.app_output;
    }

    public final AiLIRemote copy(Output output, Output app_output) {
        return new AiLIRemote(output, app_output);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AiLIRemote)) {
            return false;
        }
        AiLIRemote aiLIRemote = (AiLIRemote) other;
        return AbstractC7609s.f(this.output, aiLIRemote.output) && AbstractC7609s.f(this.app_output, aiLIRemote.app_output);
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
        return "AiLIRemote(output=" + this.output + ", app_output=" + this.app_output + ')';
    }
}
