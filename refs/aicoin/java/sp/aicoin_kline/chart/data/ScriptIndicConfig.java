package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import java.util.List;
import kk.d;
import kk.h;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00004\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0004\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000b\n\u0002\b!\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001Bs\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0003\u0012\f\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b\u0012\b\b\u0002\u0010\n\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000b\u001a\u00020\u0003\u0012\f\u0010\f\u001a\b\u0012\u0004\u0012\u00020\r0\b\u0012\b\b\u0002\u0010\u000e\u001a\u00020\u000f\u0012\b\b\u0002\u0010\u0010\u001a\u00020\u0003¢\u0006\u0004\b\u0011\u0010\u0012J\t\u0010#\u001a\u00020\u0003HÆ\u0003J\t\u0010$\u001a\u00020\u0003HÆ\u0003J\t\u0010%\u001a\u00020\u0003HÆ\u0003J\t\u0010&\u001a\u00020\u0003HÆ\u0003J\u000f\u0010'\u001a\b\u0012\u0004\u0012\u00020\t0\bHÆ\u0003J\t\u0010(\u001a\u00020\u0003HÆ\u0003J\t\u0010)\u001a\u00020\u0003HÆ\u0003J\u000f\u0010*\u001a\b\u0012\u0004\u0012\u00020\r0\bHÆ\u0003J\t\u0010+\u001a\u00020\u000fHÆ\u0003J\t\u0010,\u001a\u00020\u0003HÆ\u0003Jy\u0010-\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\u000e\b\u0002\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b2\b\b\u0002\u0010\n\u001a\u00020\u00032\b\b\u0002\u0010\u000b\u001a\u00020\u00032\u000e\b\u0002\u0010\f\u001a\b\u0012\u0004\u0012\u00020\r0\b2\b\b\u0002\u0010\u000e\u001a\u00020\u000f2\b\b\u0002\u0010\u0010\u001a\u00020\u0003HÆ\u0001J\u0013\u0010.\u001a\u00020\u000f2\b\u0010/\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00100\u001a\u000201HÖ\u0001J\t\u00102\u001a\u00020\u0003HÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0013\u0010\u0014\"\u0004\b\u0015\u0010\u0016R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0017\u0010\u0014R\u001a\u0010\u0005\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0018\u0010\u0014\"\u0004\b\u0019\u0010\u0016R\u001a\u0010\u0006\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001a\u0010\u0014\"\u0004\b\u001b\u0010\u0016R\u0017\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u001dR\u0011\u0010\n\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001e\u0010\u0014R\u0011\u0010\u000b\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010\u0014R\u0017\u0010\f\u001a\b\u0012\u0004\u0012\u00020\r0\b¢\u0006\b\n\u0000\u001a\u0004\b \u0010\u001dR\u0011\u0010\u000e\u001a\u00020\u000f¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010!R\u0011\u0010\u0010\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u0014¨\u00063"}, d2 = {"Lsp/aicoin_kline/chart/data/ScriptIndicConfig;", "", "id", "", "buildType", "title", "errorMsg", "action", "", "Lsp/aicoin_kline/chart/data/ScriptIndicAction;", "scriptRef", "pos", "colorActions", "Lsp/aicoin_kline/chart/data/ColorActions;", "isSubs", "", "communityID", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/lang/String;Ljava/lang/String;Ljava/util/List;ZLjava/lang/String;)V", "getId", "()Ljava/lang/String;", "setId", "(Ljava/lang/String;)V", "getBuildType", "getTitle", "setTitle", "getErrorMsg", "setErrorMsg", "getAction", "()Ljava/util/List;", "getScriptRef", "getPos", "getColorActions", "()Z", "getCommunityID", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "copy", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ScriptIndicConfig {
    private final List<ScriptIndicAction> action;
    private final String buildType;
    private final List<ColorActions> colorActions;
    private final String communityID;
    private String errorMsg;
    private String id;
    private final boolean isSubs;
    private final String pos;
    private final String scriptRef;
    private String title;

    public ScriptIndicConfig(String str, String str2, String str3, String str4, List<ScriptIndicAction> list, String str5, String str6, List<ColorActions> list2, boolean z10, String str7) {
        this.id = str;
        this.buildType = str2;
        this.title = str3;
        this.errorMsg = str4;
        this.action = list;
        this.scriptRef = str5;
        this.pos = str6;
        this.colorActions = list2;
        this.isSubs = z10;
        this.communityID = str7;
    }

    public /* synthetic */ ScriptIndicConfig(String str, String str2, String str3, String str4, List list, String str5, String str6, List list2, boolean z10, String str7, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? "" : str, (i10 & 2) != 0 ? "" : str2, (i10 & 4) != 0 ? "" : str3, (i10 & 8) != 0 ? "" : str4, list, (i10 & 32) != 0 ? "" : str5, (i10 & 64) != 0 ? "" : str6, list2, (i10 & 256) != 0 ? false : z10, (i10 & 512) != 0 ? "" : str7);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ ScriptIndicConfig copy$default(ScriptIndicConfig scriptIndicConfig, String str, String str2, String str3, String str4, List list, String str5, String str6, List list2, boolean z10, String str7, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = scriptIndicConfig.id;
        }
        if ((i10 & 2) != 0) {
            str2 = scriptIndicConfig.buildType;
        }
        if ((i10 & 4) != 0) {
            str3 = scriptIndicConfig.title;
        }
        if ((i10 & 8) != 0) {
            str4 = scriptIndicConfig.errorMsg;
        }
        if ((i10 & 16) != 0) {
            list = scriptIndicConfig.action;
        }
        if ((i10 & 32) != 0) {
            str5 = scriptIndicConfig.scriptRef;
        }
        if ((i10 & 64) != 0) {
            str6 = scriptIndicConfig.pos;
        }
        if ((i10 & 128) != 0) {
            list2 = scriptIndicConfig.colorActions;
        }
        if ((i10 & 256) != 0) {
            z10 = scriptIndicConfig.isSubs;
        }
        if ((i10 & 512) != 0) {
            str7 = scriptIndicConfig.communityID;
        }
        boolean z11 = z10;
        String str8 = str7;
        String str9 = str6;
        List list3 = list2;
        List list4 = list;
        String str10 = str5;
        return scriptIndicConfig.copy(str, str2, str3, str4, list4, str10, str9, list3, z11, str8);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getCommunityID() {
        return this.communityID;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getBuildType() {
        return this.buildType;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getTitle() {
        return this.title;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getErrorMsg() {
        return this.errorMsg;
    }

    public final List<ScriptIndicAction> component5() {
        return this.action;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getScriptRef() {
        return this.scriptRef;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getPos() {
        return this.pos;
    }

    public final List<ColorActions> component8() {
        return this.colorActions;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final boolean getIsSubs() {
        return this.isSubs;
    }

    public final ScriptIndicConfig copy(String id2, String buildType, String title, String errorMsg, List<ScriptIndicAction> action, String scriptRef, String pos, List<ColorActions> colorActions, boolean isSubs, String communityID) {
        return new ScriptIndicConfig(id2, buildType, title, errorMsg, action, scriptRef, pos, colorActions, isSubs, communityID);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ScriptIndicConfig)) {
            return false;
        }
        ScriptIndicConfig scriptIndicConfig = (ScriptIndicConfig) other;
        return AbstractC7609s.f(this.id, scriptIndicConfig.id) && AbstractC7609s.f(this.buildType, scriptIndicConfig.buildType) && AbstractC7609s.f(this.title, scriptIndicConfig.title) && AbstractC7609s.f(this.errorMsg, scriptIndicConfig.errorMsg) && AbstractC7609s.f(this.action, scriptIndicConfig.action) && AbstractC7609s.f(this.scriptRef, scriptIndicConfig.scriptRef) && AbstractC7609s.f(this.pos, scriptIndicConfig.pos) && AbstractC7609s.f(this.colorActions, scriptIndicConfig.colorActions) && this.isSubs == scriptIndicConfig.isSubs && AbstractC7609s.f(this.communityID, scriptIndicConfig.communityID);
    }

    public final List<ScriptIndicAction> getAction() {
        return this.action;
    }

    public final String getBuildType() {
        return this.buildType;
    }

    public final List<ColorActions> getColorActions() {
        return this.colorActions;
    }

    public final String getCommunityID() {
        return this.communityID;
    }

    public final String getErrorMsg() {
        return this.errorMsg;
    }

    public final String getId() {
        return this.id;
    }

    public final String getPos() {
        return this.pos;
    }

    public final String getScriptRef() {
        return this.scriptRef;
    }

    public final String getTitle() {
        return this.title;
    }

    public int hashCode() {
        return this.communityID.hashCode() + ((Boolean.hashCode(this.isSubs) + ((this.colorActions.hashCode() + d.a(this.pos, d.a(this.scriptRef, (this.action.hashCode() + d.a(this.errorMsg, d.a(this.title, d.a(this.buildType, this.id.hashCode() * 31, 31), 31), 31)) * 31, 31), 31)) * 31)) * 31);
    }

    public final boolean isSubs() {
        return this.isSubs;
    }

    public final void setErrorMsg(String str) {
        this.errorMsg = str;
    }

    public final void setId(String str) {
        this.id = str;
    }

    public final void setTitle(String str) {
        this.title = str;
    }

    public String toString() {
        StringBuilder sb2 = new StringBuilder("ScriptIndicConfig(id=");
        sb2.append(this.id);
        sb2.append(", buildType=");
        sb2.append(this.buildType);
        sb2.append(", title=");
        sb2.append(this.title);
        sb2.append(", errorMsg=");
        sb2.append(this.errorMsg);
        sb2.append(", action=");
        sb2.append(this.action);
        sb2.append(", scriptRef=");
        sb2.append(this.scriptRef);
        sb2.append(", pos=");
        sb2.append(this.pos);
        sb2.append(", colorActions=");
        sb2.append(this.colorActions);
        sb2.append(", isSubs=");
        sb2.append(this.isSubs);
        sb2.append(", communityID=");
        return h.a(sb2, this.communityID, ')');
    }
}
