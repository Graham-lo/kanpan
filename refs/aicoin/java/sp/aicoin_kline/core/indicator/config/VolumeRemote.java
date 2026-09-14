package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import java.util.List;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0002\u001c\u001dB/\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\b\u0010\tJ\u000b\u0010\u0010\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0011\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0012\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0003HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\rR\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000b¨\u0006\u001e"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VolumeRemote;", "", "input", "Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Input;", "output", "Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output;", "app_output", "app_input", "<init>", "(Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Input;Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output;Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output;Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Input;)V", "getInput", "()Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Input;", "getOutput", "()Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output;", "getApp_output", "getApp_input", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "", "Input", "Output", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class VolumeRemote {
    private final Input app_input;
    private final Output app_output;
    private final Input input;
    private final Output output;

    @Keep
    @Metadata(d1 = {"\u0000$\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0010\b\n\u0002\b\u0007\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u0017\u0012\u000e\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0011\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u001b\u0010\n\u001a\u00020\u00002\u0010\b\u0002\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\u000b\u001a\u00020\f2\b\u0010\r\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000e\u001a\u00020\u0004HÖ\u0001J\t\u0010\u000f\u001a\u00020\u0010HÖ\u0001R\u0019\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\b¨\u0006\u0011"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Input;", "", "ma", "", "", "<init>", "(Ljava/util/List;)V", "getMa", "()Ljava/util/List;", "component1", "copy", "equals", "", "other", "hashCode", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Input {
        private final List<Integer> ma;

        public Input(List<Integer> list) {
            this.ma = list;
        }

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ Input copy$default(Input input, List list, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                list = input.ma;
            }
            return input.copy(list);
        }

        public final List<Integer> component1() {
            return this.ma;
        }

        public final Input copy(List<Integer> ma2) {
            return new Input(ma2);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return (other instanceof Input) && AbstractC7609s.f(this.ma, ((Input) other).ma);
        }

        public final List<Integer> getMa() {
            return this.ma;
        }

        public int hashCode() {
            List<Integer> list = this.ma;
            if (list == null) {
                return 0;
            }
            return list.hashCode();
        }

        public String toString() {
            return "Input(ma=" + this.ma + ')';
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000*\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b \n\u0002\u0010\b\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0001+Bm\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\u0010\b\u0002\u0010\u0006\u001a\n\u0012\u0004\u0012\u00020\b\u0018\u00010\u0007\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0005¢\u0006\u0004\b\u000e\u0010\u000fJ\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0013J\u0011\u0010\u001e\u001a\n\u0012\u0004\u0012\u00020\b\u0018\u00010\u0007HÆ\u0003J\u0010\u0010\u001f\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0013J\u000b\u0010 \u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010!\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0013J\u000b\u0010\"\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010#\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u0013Jt\u0010$\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\u0010\b\u0002\u0010\u0006\u001a\n\u0012\u0004\u0012\u00020\b\u0018\u00010\u00072\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0005HÆ\u0001¢\u0006\u0002\u0010%J\u0013\u0010&\u001a\u00020\u00052\b\u0010'\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010(\u001a\u00020)HÖ\u0001J\t\u0010*\u001a\u00020\u0003HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001a\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0012\u0010\u0013R\u0019\u0010\u0006\u001a\n\u0012\u0004\u0012\u00020\b\u0018\u00010\u0007¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0016R\u001a\u0010\t\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0017\u0010\u0013R\u0018\u0010\n\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0011R\u001a\u0010\u000b\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u0019\u0010\u0013R\u0018\u0010\f\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u0011R\u001a\u0010\r\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0014\u001a\u0004\b\u001b\u0010\u0013¨\u0006,"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output;", "", "estimatedColor", "", "estimatedDisabled", "", "ma", "", "Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output$Ma;", "volumeDisabled", "volumeFallColor", "volumeFallFill", "volumeRiseColor", "volumeRiseFill", "<init>", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/util/List;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;)V", "getEstimatedColor", "()Ljava/lang/String;", "getEstimatedDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getMa", "()Ljava/util/List;", "getVolumeDisabled", "getVolumeFallColor", "getVolumeFallFill", "getVolumeRiseColor", "getVolumeRiseFill", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "copy", "(Ljava/lang/String;Ljava/lang/Boolean;Ljava/util/List;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Boolean;)Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output;", "equals", "other", "hashCode", "", "toString", "Ma", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Output {

        @SerializedName("estimated_color")
        private final String estimatedColor;

        @SerializedName("estimated_disabled")
        private final Boolean estimatedDisabled;
        private final List<Ma> ma;

        @SerializedName("volume_disabled")
        private final Boolean volumeDisabled;

        @SerializedName("volume_fall_color")
        private final String volumeFallColor;

        @SerializedName("volume_fall_fill")
        private final Boolean volumeFallFill;

        @SerializedName("volume_rise_color")
        private final String volumeRiseColor;

        @SerializedName("volume_rise_fill")
        private final Boolean volumeRiseFill;

        @Keep
        @Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B+\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007¢\u0006\u0004\b\b\u0010\tJ\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u000bJ\u000b\u0010\u0013\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010\u0014\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010\u0010J2\u0010\u0015\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007HÆ\u0001¢\u0006\u0002\u0010\u0016J\u0013\u0010\u0017\u001a\u00020\u00032\b\u0010\u0018\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0019\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001a\u001a\u00020\u0005HÖ\u0001R\u001a\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\f\u001a\u0004\b\n\u0010\u000bR\u0018\u0010\u0004\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001a\u0010\u0006\u001a\u0004\u0018\u00010\u00078\u0006X\u0087\u0004¢\u0006\n\n\u0002\u0010\u0011\u001a\u0004\b\u000f\u0010\u0010¨\u0006\u001b"}, d2 = {"Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output$Ma;", "", "maDisabled", "", "maLineColor", "", "maLineWidth", "", "<init>", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)V", "getMaDisabled", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getMaLineColor", "()Ljava/lang/String;", "getMaLineWidth", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "component1", "component2", "component3", "copy", "(Ljava/lang/Boolean;Ljava/lang/String;Ljava/lang/Integer;)Lsp/aicoin_kline/core/indicator/config/VolumeRemote$Output$Ma;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
        public static final /* data */ class Ma {

            @SerializedName("ma_disabled")
            private final Boolean maDisabled;

            @SerializedName("ma_lineColor")
            private final String maLineColor;

            @SerializedName("ma_lineWidth")
            private final Integer maLineWidth;

            public Ma() {
                this(null, null, null, 7, null);
            }

            public Ma(Boolean bool, String str, Integer num) {
                this.maDisabled = bool;
                this.maLineColor = str;
                this.maLineWidth = num;
            }

            public /* synthetic */ Ma(Boolean bool, String str, Integer num, int i10, DefaultConstructorMarker defaultConstructorMarker) {
                this((i10 & 1) != 0 ? null : bool, (i10 & 2) != 0 ? null : str, (i10 & 4) != 0 ? null : num);
            }

            public static /* synthetic */ Ma copy$default(Ma ma2, Boolean bool, String str, Integer num, int i10, Object obj) {
                if ((i10 & 1) != 0) {
                    bool = ma2.maDisabled;
                }
                if ((i10 & 2) != 0) {
                    str = ma2.maLineColor;
                }
                if ((i10 & 4) != 0) {
                    num = ma2.maLineWidth;
                }
                return ma2.copy(bool, str, num);
            }

            /* JADX INFO: renamed from: component1, reason: from getter */
            public final Boolean getMaDisabled() {
                return this.maDisabled;
            }

            /* JADX INFO: renamed from: component2, reason: from getter */
            public final String getMaLineColor() {
                return this.maLineColor;
            }

            /* JADX INFO: renamed from: component3, reason: from getter */
            public final Integer getMaLineWidth() {
                return this.maLineWidth;
            }

            public final Ma copy(Boolean maDisabled, String maLineColor, Integer maLineWidth) {
                return new Ma(maDisabled, maLineColor, maLineWidth);
            }

            public boolean equals(Object other) {
                if (this == other) {
                    return true;
                }
                if (!(other instanceof Ma)) {
                    return false;
                }
                Ma ma2 = (Ma) other;
                return AbstractC7609s.f(this.maDisabled, ma2.maDisabled) && AbstractC7609s.f(this.maLineColor, ma2.maLineColor) && AbstractC7609s.f(this.maLineWidth, ma2.maLineWidth);
            }

            public final Boolean getMaDisabled() {
                return this.maDisabled;
            }

            public final String getMaLineColor() {
                return this.maLineColor;
            }

            public final Integer getMaLineWidth() {
                return this.maLineWidth;
            }

            public int hashCode() {
                Boolean bool = this.maDisabled;
                int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
                String str = this.maLineColor;
                int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
                Integer num = this.maLineWidth;
                return iHashCode2 + (num != null ? num.hashCode() : 0);
            }

            public String toString() {
                StringBuilder sb2 = new StringBuilder("Ma(maDisabled=");
                sb2.append(this.maDisabled);
                sb2.append(", maLineColor=");
                sb2.append(this.maLineColor);
                sb2.append(", maLineWidth=");
                return kk.b.a(sb2, this.maLineWidth, ')');
            }
        }

        public Output() {
            this(null, null, null, null, null, null, null, null, 255, null);
        }

        public Output(String str, Boolean bool, List<Ma> list, Boolean bool2, String str2, Boolean bool3, String str3, Boolean bool4) {
            this.estimatedColor = str;
            this.estimatedDisabled = bool;
            this.ma = list;
            this.volumeDisabled = bool2;
            this.volumeFallColor = str2;
            this.volumeFallFill = bool3;
            this.volumeRiseColor = str3;
            this.volumeRiseFill = bool4;
        }

        public /* synthetic */ Output(String str, Boolean bool, List list, Boolean bool2, String str2, Boolean bool3, String str3, Boolean bool4, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? null : str, (i10 & 2) != 0 ? null : bool, (i10 & 4) != 0 ? null : list, (i10 & 8) != 0 ? null : bool2, (i10 & 16) != 0 ? null : str2, (i10 & 32) != 0 ? null : bool3, (i10 & 64) != 0 ? null : str3, (i10 & 128) != 0 ? null : bool4);
        }

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ Output copy$default(Output output, String str, Boolean bool, List list, Boolean bool2, String str2, Boolean bool3, String str3, Boolean bool4, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                str = output.estimatedColor;
            }
            if ((i10 & 2) != 0) {
                bool = output.estimatedDisabled;
            }
            if ((i10 & 4) != 0) {
                list = output.ma;
            }
            if ((i10 & 8) != 0) {
                bool2 = output.volumeDisabled;
            }
            if ((i10 & 16) != 0) {
                str2 = output.volumeFallColor;
            }
            if ((i10 & 32) != 0) {
                bool3 = output.volumeFallFill;
            }
            if ((i10 & 64) != 0) {
                str3 = output.volumeRiseColor;
            }
            if ((i10 & 128) != 0) {
                bool4 = output.volumeRiseFill;
            }
            String str4 = str3;
            Boolean bool5 = bool4;
            String str5 = str2;
            Boolean bool6 = bool3;
            return output.copy(str, bool, list, bool2, str5, bool6, str4, bool5);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final String getEstimatedColor() {
            return this.estimatedColor;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Boolean getEstimatedDisabled() {
            return this.estimatedDisabled;
        }

        public final List<Ma> component3() {
            return this.ma;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Boolean getVolumeDisabled() {
            return this.volumeDisabled;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final String getVolumeFallColor() {
            return this.volumeFallColor;
        }

        /* JADX INFO: renamed from: component6, reason: from getter */
        public final Boolean getVolumeFallFill() {
            return this.volumeFallFill;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final String getVolumeRiseColor() {
            return this.volumeRiseColor;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Boolean getVolumeRiseFill() {
            return this.volumeRiseFill;
        }

        public final Output copy(String estimatedColor, Boolean estimatedDisabled, List<Ma> ma2, Boolean volumeDisabled, String volumeFallColor, Boolean volumeFallFill, String volumeRiseColor, Boolean volumeRiseFill) {
            return new Output(estimatedColor, estimatedDisabled, ma2, volumeDisabled, volumeFallColor, volumeFallFill, volumeRiseColor, volumeRiseFill);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Output)) {
                return false;
            }
            Output output = (Output) other;
            return AbstractC7609s.f(this.estimatedColor, output.estimatedColor) && AbstractC7609s.f(this.estimatedDisabled, output.estimatedDisabled) && AbstractC7609s.f(this.ma, output.ma) && AbstractC7609s.f(this.volumeDisabled, output.volumeDisabled) && AbstractC7609s.f(this.volumeFallColor, output.volumeFallColor) && AbstractC7609s.f(this.volumeFallFill, output.volumeFallFill) && AbstractC7609s.f(this.volumeRiseColor, output.volumeRiseColor) && AbstractC7609s.f(this.volumeRiseFill, output.volumeRiseFill);
        }

        public final String getEstimatedColor() {
            return this.estimatedColor;
        }

        public final Boolean getEstimatedDisabled() {
            return this.estimatedDisabled;
        }

        public final List<Ma> getMa() {
            return this.ma;
        }

        public final Boolean getVolumeDisabled() {
            return this.volumeDisabled;
        }

        public final String getVolumeFallColor() {
            return this.volumeFallColor;
        }

        public final Boolean getVolumeFallFill() {
            return this.volumeFallFill;
        }

        public final String getVolumeRiseColor() {
            return this.volumeRiseColor;
        }

        public final Boolean getVolumeRiseFill() {
            return this.volumeRiseFill;
        }

        public int hashCode() {
            String str = this.estimatedColor;
            int iHashCode = (str == null ? 0 : str.hashCode()) * 31;
            Boolean bool = this.estimatedDisabled;
            int iHashCode2 = (iHashCode + (bool == null ? 0 : bool.hashCode())) * 31;
            List<Ma> list = this.ma;
            int iHashCode3 = (iHashCode2 + (list == null ? 0 : list.hashCode())) * 31;
            Boolean bool2 = this.volumeDisabled;
            int iHashCode4 = (iHashCode3 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            String str2 = this.volumeFallColor;
            int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
            Boolean bool3 = this.volumeFallFill;
            int iHashCode6 = (iHashCode5 + (bool3 == null ? 0 : bool3.hashCode())) * 31;
            String str3 = this.volumeRiseColor;
            int iHashCode7 = (iHashCode6 + (str3 == null ? 0 : str3.hashCode())) * 31;
            Boolean bool4 = this.volumeRiseFill;
            return iHashCode7 + (bool4 != null ? bool4.hashCode() : 0);
        }

        public String toString() {
            return "Output(estimatedColor=" + this.estimatedColor + ", estimatedDisabled=" + this.estimatedDisabled + ", ma=" + this.ma + ", volumeDisabled=" + this.volumeDisabled + ", volumeFallColor=" + this.volumeFallColor + ", volumeFallFill=" + this.volumeFallFill + ", volumeRiseColor=" + this.volumeRiseColor + ", volumeRiseFill=" + this.volumeRiseFill + ')';
        }
    }

    public VolumeRemote(Input input, Output output, Output output2, Input input2) {
        this.input = input;
        this.output = output;
        this.app_output = output2;
        this.app_input = input2;
    }

    public static /* synthetic */ VolumeRemote copy$default(VolumeRemote volumeRemote, Input input, Output output, Output output2, Input input2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            input = volumeRemote.input;
        }
        if ((i10 & 2) != 0) {
            output = volumeRemote.output;
        }
        if ((i10 & 4) != 0) {
            output2 = volumeRemote.app_output;
        }
        if ((i10 & 8) != 0) {
            input2 = volumeRemote.app_input;
        }
        return volumeRemote.copy(input, output, output2, input2);
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

    public final VolumeRemote copy(Input input, Output output, Output app_output, Input app_input) {
        return new VolumeRemote(input, output, app_output, app_input);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof VolumeRemote)) {
            return false;
        }
        VolumeRemote volumeRemote = (VolumeRemote) other;
        return AbstractC7609s.f(this.input, volumeRemote.input) && AbstractC7609s.f(this.output, volumeRemote.output) && AbstractC7609s.f(this.app_output, volumeRemote.app_output) && AbstractC7609s.f(this.app_input, volumeRemote.app_input);
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
        return "VolumeRemote(input=" + this.input + ", output=" + this.output + ", app_output=" + this.app_output + ", app_input=" + this.app_input + ')';
    }
}
