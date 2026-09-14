package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AlligatorRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Input;Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Output;Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Output;Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AlligatorRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0018\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001BC\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\b\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\t\u0010\nJ\u0010\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0015\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0016\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0017\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJ\u0010\u0010\u0018\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\fJV\u0010\u0019\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u001aJ\u0013\u0010\u001b\u001a\u00020\u001c2\b\u0010\u001d\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001e\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001f\u001a\u00020 HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000b\u0010\fR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000e\u0010\fR\u0015\u0010\u0005\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000f\u0010\fR\u0015\u0010\u0006\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0010\u0010\fR\u0015\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0011\u0010\fR\u0015\u0010\b\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u0012\u0010\f¨\u0006!"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Input;", "", "jawCycle", "", "jawOffset", "lipsCycle", "lipsOffset", "teethCycle", "teethOffset", "<init>", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)V", "getJawCycle", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getJawOffset", "getLipsCycle", "getLipsOffset", "getTeethCycle", "getTeethOffset", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Input;", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final Integer jawCycle;
        private final Integer jawOffset;
        private final Integer lipsCycle;
        private final Integer lipsOffset;
        private final Integer teethCycle;
        private final Integer teethOffset;

        public Input(Integer num, Integer num2, Integer num3, Integer num4, Integer num5, Integer num6) {
            this.jawCycle = num;
            this.jawOffset = num2;
            this.lipsCycle = num3;
            this.lipsOffset = num4;
            this.teethCycle = num5;
            this.teethOffset = num6;
        }

        public static /* synthetic */ Input copy$default(Input input, Integer num, Integer num2, Integer num3, Integer num4, Integer num5, Integer num6, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                num = input.jawCycle;
            }
            if ((i10 & 2) != 0) {
                num2 = input.jawOffset;
            }
            if ((i10 & 4) != 0) {
                num3 = input.lipsCycle;
            }
            if ((i10 & 8) != 0) {
                num4 = input.lipsOffset;
            }
            if ((i10 & 16) != 0) {
                num5 = input.teethCycle;
            }
            if ((i10 & 32) != 0) {
                num6 = input.teethOffset;
            }
            Integer num7 = num5;
            Integer num8 = num6;
            return input.copy(num, num2, num3, num4, num7, num8);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Integer getJawCycle() {
            return this.jawCycle;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Integer getJawOffset() {
            return this.jawOffset;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getLipsCycle() {
            return this.lipsCycle;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Integer getLipsOffset() {
            return this.lipsOffset;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Integer getTeethCycle() {
            return this.teethCycle;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getTeethOffset() {
            return this.teethOffset;
        }

        public final Input copy(Integer jawCycle, Integer jawOffset, Integer lipsCycle, Integer lipsOffset, Integer teethCycle, Integer teethOffset) {
            return new Input(jawCycle, jawOffset, lipsCycle, lipsOffset, teethCycle, teethOffset);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Input)) {
                return false;
            }
            Input input = (Input) other;
            return AbstractC7609s.f(this.jawCycle, input.jawCycle) && AbstractC7609s.f(this.jawOffset, input.jawOffset) && AbstractC7609s.f(this.lipsCycle, input.lipsCycle) && AbstractC7609s.f(this.lipsOffset, input.lipsOffset) && AbstractC7609s.f(this.teethCycle, input.teethCycle) && AbstractC7609s.f(this.teethOffset, input.teethOffset);
        }

        public final Integer getJawCycle() {
            return this.jawCycle;
        }

        public final Integer getJawOffset() {
            return this.jawOffset;
        }

        public final Integer getLipsCycle() {
            return this.lipsCycle;
        }

        public final Integer getLipsOffset() {
            return this.lipsOffset;
        }

        public final Integer getTeethCycle() {
            return this.teethCycle;
        }

        public final Integer getTeethOffset() {
            return this.teethOffset;
        }

        public int hashCode() {
            Integer num = this.jawCycle;
            int iHashCode = (num == null ? 0 : num.hashCode()) * 31;
            Integer num2 = this.jawOffset;
            int iHashCode2 = (iHashCode + (num2 == null ? 0 : num2.hashCode())) * 31;
            Integer num3 = this.lipsCycle;
            int iHashCode3 = (iHashCode2 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Integer num4 = this.lipsOffset;
            int iHashCode4 = (iHashCode3 + (num4 == null ? 0 : num4.hashCode())) * 31;
            Integer num5 = this.teethCycle;
            int iHashCode5 = (iHashCode4 + (num5 == null ? 0 : num5.hashCode())) * 31;
            Integer num6 = this.teethOffset;
            return iHashCode5 + (num6 != null ? num6.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Input(jawCycle=");
            sb2.append(this.jawCycle);
            sb2.append(", jawOffset=");
            sb2.append(this.jawOffset);
            sb2.append(", lipsCycle=");
            sb2.append(this.lipsCycle);
            sb2.append(", lipsOffset=");
            sb2.append(this.lipsOffset);
            sb2.append(", teethCycle=");
            sb2.append(this.teethCycle);
            sb2.append(", teethOffset=");
            return kk.b.a(sb2, this.teethOffset, ')');
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b&\b\u0087\b\u0018\u00002\u00020\u0001Bs\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\u000e\u0010\u000fJ\u0010\u0010\u001e\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010\u001f\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010 \u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016J\u0010\u0010!\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010\"\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010#\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016J\u0010\u0010$\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0011J\u000b\u0010%\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010&\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0016Jz\u0010'\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010(J\u0013\u0010)\u001a\u00020\u00032\b\u0010*\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010+\u001a\u00020\u0007HÖ\u0001J\t\u0010,\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u0010\u0010\u0011R\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0014R\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u0015\u0010\u0016R\u001a\u0010\b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u0018\u0010\u0011R\u0018\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0014R\u001a\u0010\n\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u001a\u0010\u0016R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0012\u001a\u0004\b\u001b\u0010\u0011R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0014R\u001a\u0010\r\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u001d\u0010\u0016¨\u0006-"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Output;", "", "jawDisabled", "", "jawLineColor", "", "jawLineWidth", "", "lipsDisabled", "lipsLineColor", "lipsLineWidth", "teethDisabled", "teethLineColor", "teethLineWidth", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getJawDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getJawLineColor", "()Ljava/lang/String;", "getJawLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getLipsDisabled", "getLipsLineColor", "getLipsLineWidth", "getTeethDisabled", "getTeethLineColor", "getTeethLineWidth", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/AlligatorRemote$Output;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("jaw_disabled")
        private final Boolean jawDisabled;

        @SerializedName("jaw_lineColor")
        private final String jawLineColor;

        @SerializedName("jaw_lineWidth")
        private final Integer jawLineWidth;

        @SerializedName("lips_disabled")
        private final Boolean lipsDisabled;

        @SerializedName("lips_lineColor")
        private final String lipsLineColor;

        @SerializedName("lips_lineWidth")
        private final Integer lipsLineWidth;

        @SerializedName("teeth_disabled")
        private final Boolean teethDisabled;

        @SerializedName("teeth_lineColor")
        private final String teethLineColor;

        @SerializedName("teeth_lineWidth")
        private final Integer teethLineWidth;

        public Output() {
            this(null, null, null, null, null, null, null, null, null, 511, null);
        }

        public Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3) {
            this.jawDisabled = bool;
            this.jawLineColor = str;
            this.jawLineWidth = num;
            this.lipsDisabled = bool2;
            this.lipsLineColor = str2;
            this.lipsLineWidth = num2;
            this.teethDisabled = bool3;
            this.teethLineColor = str3;
            this.teethLineWidth = num3;
        }

        public /* synthetic */ Output(Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : num2, (i10 & 64) != 0 ? null : bool3, (i10 & 128) != 0 ? null : str3, (i10 & 256) != 0 ? null : num3);
        }

        public static /* synthetic */ Output copy$default(Output output, Boolean bool, String str, Integer num, Boolean bool2, String str2, Integer num2, Boolean bool3, String str3, Integer num3, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = output.jawDisabled;
            }
            if ((i10 & 2) != 0) {
                str = output.jawLineColor;
            }
            if ((i10 & 4) != 0) {
                num = output.jawLineWidth;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.lipsDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.lipsLineColor;
            }
            if ((i10 & 32) != 0) {
                num2 = output.lipsLineWidth;
            }
            if ((i10 & 64) != 0) {
                bool3 = output.teethDisabled;
            }
            if ((i10 & 128) != 0) {
                str3 = output.teethLineColor;
            }
            if ((i10 & 256) != 0) {
                num3 = output.teethLineWidth;
            }
            String str4 = str3;
            Integer num4 = num3;
            Integer num5 = num2;
            Boolean bool4 = bool3;
            String str5 = str2;
            Integer num6 = num;
            return output.copy(bool, str, num6, bool2, str5, num5, bool4, str4, num4);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getJawDisabled() {
            return this.jawDisabled;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getJawLineColor() {
            return this.jawLineColor;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getJawLineWidth() {
            return this.jawLineWidth;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getLipsDisabled() {
            return this.lipsDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getLipsLineColor() {
            return this.lipsLineColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Integer getLipsLineWidth() {
            return this.lipsLineWidth;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final Boolean getTeethDisabled() {
            return this.teethDisabled;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final String getTeethLineColor() {
            return this.teethLineColor;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Integer getTeethLineWidth() {
            return this.teethLineWidth;
        }

        public final Output copy(Boolean jawDisabled, String jawLineColor, Integer jawLineWidth, Boolean lipsDisabled, String lipsLineColor, Integer lipsLineWidth, Boolean teethDisabled, String teethLineColor, Integer teethLineWidth) {
            return new Output(jawDisabled, jawLineColor, jawLineWidth, lipsDisabled, lipsLineColor, lipsLineWidth, teethDisabled, teethLineColor, teethLineWidth);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.jawDisabled, output.jawDisabled) && AbstractC7609s.f(this.jawLineColor, output.jawLineColor) && AbstractC7609s.f(this.jawLineWidth, output.jawLineWidth) && AbstractC7609s.f(this.lipsDisabled, output.lipsDisabled) && AbstractC7609s.f(this.lipsLineColor, output.lipsLineColor) && AbstractC7609s.f(this.lipsLineWidth, output.lipsLineWidth) && AbstractC7609s.f(this.teethDisabled, output.teethDisabled) && AbstractC7609s.f(this.teethLineColor, output.teethLineColor) && AbstractC7609s.f(this.teethLineWidth, output.teethLineWidth);
        }

        public final Boolean getJawDisabled() {
            return this.jawDisabled;
        }

        public final String getJawLineColor() {
            return this.jawLineColor;
        }

        public final Integer getJawLineWidth() {
            return this.jawLineWidth;
        }

        public final Boolean getLipsDisabled() {
            return this.lipsDisabled;
        }

        public final String getLipsLineColor() {
            return this.lipsLineColor;
        }

        public final Integer getLipsLineWidth() {
            return this.lipsLineWidth;
        }

        public final Boolean getTeethDisabled() {
            return this.teethDisabled;
        }

        public final String getTeethLineColor() {
            return this.teethLineColor;
        }

        public final Integer getTeethLineWidth() {
            return this.teethLineWidth;
        }

        public int hashCode() {
            Boolean bool = this.jawDisabled;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            String str = this.jawLineColor;
            int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
            Integer num = this.jawLineWidth;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Boolean bool2 = this.lipsDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.lipsLineColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Integer num2 = this.lipsLineWidth;
            int iHashCode6 = (iHashCode5 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool3 = this.teethDisabled;
            int iHashCode7 = (iHashCode6 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.teethLineColor;
            int iHashCode8 = (iHashCode7 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Integer num3 = this.teethLineWidth;
            return iHashCode8 + (num3 != null ? num3.hashCode() : 0);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("Output(jawDisabled=");
            sb2.append(this.jawDisabled);
            sb2.append(", jawLineColor=");
            sb2.append(this.jawLineColor);
            sb2.append(", jawLineWidth=");
            sb2.append(this.jawLineWidth);
            sb2.append(", lipsDisabled=");
            sb2.append(this.lipsDisabled);
            sb2.append(", lipsLineColor=");
            sb2.append(this.lipsLineColor);
            sb2.append(", lipsLineWidth=");
            sb2.append(this.lipsLineWidth);
            sb2.append(", teethDisabled=");
            sb2.append(this.teethDisabled);
            sb2.append(", teethLineColor=");
            sb2.append(this.teethLineColor);
            sb2.append(", teethLineWidth=");
            return kk.b.a(sb2, this.teethLineWidth, ')');
        }
    }

    public AlligatorRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ AlligatorRemote copy$default(AlligatorRemote alligatorRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = alligatorRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = alligatorRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = alligatorRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = alligatorRemote.app_input;
        }
        return alligatorRemote.copy(input, output, output2, input2);
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

    public final AlligatorRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new AlligatorRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AlligatorRemote)) {
            return false;
        }
        AlligatorRemote alligatorRemote = (AlligatorRemote) other;
        return AbstractC7609s.f(this.input, alligatorRemote.input) && AbstractC7609s.f(this.output, alligatorRemote.output) && AbstractC7609s.f(this.app_output, alligatorRemote.app_output) && AbstractC7609s.f(this.app_input, alligatorRemote.app_input);
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
        return "AlligatorRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
