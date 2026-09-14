package Sj;

import android.os.Parcel;
import android.os.Parcelable;

/* JADX INFO: loaded from: classes7.dex */
public class i implements Parcelable {
    public static final Parcelable.Creator<i> CREATOR = new a();

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final int f20801a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final int f20802b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final double f20803c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final double f20804d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final long f20805e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final String f20806f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final String f20807g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public String f20808h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public String f20809i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public String f20810j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public boolean f20811k;

    public class a implements Parcelable.Creator {
        @Override // android.os.Parcelable.Creator
        /* JADX INFO: renamed from: a, reason: merged with bridge method [inline-methods] */
        public i createFromParcel(Parcel parcel) {
            return new i(parcel);
        }

        @Override // android.os.Parcelable.Creator
        /* JADX INFO: renamed from: b, reason: merged with bridge method [inline-methods] */
        public i[] newArray(int i10) {
            return new i[i10];
        }
    }

    public i(int i10, int i11, String str, String str2, String str3, double d10, double d11, long j10) {
        this.f20801a = i10;
        this.f20802b = i11;
        this.f20806f = str;
        this.f20807g = str2;
        this.f20803c = d10;
        this.f20804d = d11;
        this.f20805e = j10;
    }

    public i(Parcel parcel) {
        this.f20801a = parcel.readInt();
        this.f20802b = parcel.readInt();
        this.f20803c = parcel.readDouble();
        this.f20804d = parcel.readDouble();
        this.f20805e = parcel.readLong();
        this.f20806f = parcel.readString();
        this.f20807g = parcel.readString();
        this.f20808h = parcel.readString();
        this.f20809i = parcel.readString();
        this.f20810j = parcel.readString();
        this.f20811k = parcel.readByte() != 0;
    }

    public String a() {
        return this.f20807g;
    }

    public String b() {
        return this.f20809i;
    }

    public long c() {
        return this.f20805e;
    }

    public String d() {
        return this.f20810j;
    }

    @Override // android.os.Parcelable
    public int describeContents() {
        return 0;
    }

    public String e() {
        return this.f20808h;
    }

    public int f() {
        return this.f20802b;
    }

    public double g() {
        return this.f20803c;
    }

    public String h() {
        return this.f20806f;
    }

    public int i() {
        return this.f20801a;
    }

    public boolean j() {
        return this.f20811k;
    }

    public void l(String str) {
        this.f20809i = str;
    }

    public void m(String str) {
        this.f20810j = str;
    }

    public void n(String str) {
        this.f20808h = str;
    }

    public void o(boolean z10) {
        this.f20811k = z10;
    }

    public String toString() {
        return "{price:" + g() + ", type:" + i() + ", createTime:" + c() + "}";
    }

    @Override // android.os.Parcelable
    public void writeToParcel(Parcel parcel, int i10) {
        parcel.writeInt(this.f20801a);
        parcel.writeInt(this.f20802b);
        parcel.writeDouble(this.f20803c);
        parcel.writeDouble(this.f20804d);
        parcel.writeLong(this.f20805e);
        parcel.writeString(this.f20806f);
        parcel.writeString(this.f20807g);
        parcel.writeString(this.f20808h);
        parcel.writeString(this.f20809i);
        parcel.writeString(this.f20810j);
        parcel.writeByte(this.f20811k ? (byte) 1 : (byte) 0);
    }
}
